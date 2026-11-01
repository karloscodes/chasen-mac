import Foundation
import Testing
@testable import ChasenKit

@Suite("A question for one server")
struct AskTests {
    @Test("names the app and the server, and returns what the CLI prints")
    func asks() async throws {
        let ask = Ask(cli: try script(#"echo "$*"; echo "$CHASEN_NO_UPDATE_CHECK""#), server: "ssh://ubuntu@203.0.113.5")

        let output = try await ask.text("status", app: "shop")

        #expect(output == "status -a shop --server ssh://ubuntu@203.0.113.5\n1\n")
    }

    @Test("asks about the server with no app")
    func server() async throws {
        let ask = Ask(cli: try script(#"echo "$*""#), server: "ssh://ubuntu@203.0.113.5")

        #expect(try await ask.text("load") == "load --server ssh://ubuntu@203.0.113.5\n")
    }

    @Test("fails with the error of the CLI")
    func fails() async throws {
        let ask = Ask(cli: try script("echo 'Error: no such app' >&2; exit 1"), server: "ssh://ubuntu@203.0.113.5")

        await #expect(throws: Ask.Failure("Error: no such app")) {
            try await ask.text("status", app: "gone")
        }
    }

    @Test("ends the CLI when nobody waits for the answer")
    func cancels() async throws {
        let mark = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ask = Ask(cli: try script("trap 'echo stopped > \(mark.path); exit 1' TERM; touch \(ready.path); sleep 5 & wait"), server: "ssh://ubuntu@203.0.113.5")

        let waiting = Task { try await ask.text("status", app: "shop") }
        while !FileManager.default.fileExists(atPath: ready.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        waiting.cancel()
        _ = await waiting.result

        #expect(FileManager.default.fileExists(atPath: mark.path))
    }

    @Test("follows the lines of a command until it stops")
    func follows() async throws {
        let ask = Ask(cli: try script(#"echo "$*"; printf '\033[31mGET /up 200\033[0m\n'"#), server: "ssh://ubuntu@203.0.113.5")
        let (lines, add) = AsyncStream.makeStream(of: String.self)

        let process = try ask.follow("logs", app: "shop", line: { add.yield($0) }, ended: { add.finish() })
        var seen: [String] = []
        for await line in lines {
            seen.append(line)
        }

        #expect(seen == ["logs -a shop --server ssh://ubuntu@203.0.113.5", "GET /up 200"])
        #expect(!process.isRunning)
    }

    func script(_ body: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
}
