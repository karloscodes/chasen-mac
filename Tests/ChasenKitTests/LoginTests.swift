import Foundation
import Testing
@testable import ChasenKit

@Suite("A login with no terminal")
struct LoginTests {
    @Test("gives ssh a way to ask, and says what the CLI says")
    func worked() async throws {
        let cli = try script("""
        echo "$1 $2 $3"
        echo "$SSH_ASKPASS $SSH_ASKPASS_REQUIRE $CHASEN_NO_UPDATE_CHECK"
        """)

        let run = try await login(cli)

        #expect(run.lines == ["add server root@203.0.113.5", "/path/of/askpass force 1"])
        #expect(run.worked)
    }

    @Test("fails with the error of the CLI")
    func failed() async throws {
        let cli = try script("""
        echo "Error: cannot log in to the server through SSH" >&2
        exit 1
        """)

        let run = try await login(cli)

        #expect(run.lines == ["Error: cannot log in to the server through SSH"])
        #expect(!run.worked)
    }

    func script(_ body: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    func login(_ cli: URL) async throws -> (lines: [String], worked: Bool) {
        let (events, add) = AsyncStream.makeStream(of: (line: String?, worked: Bool).self)
        _ = try addServer("root@203.0.113.5", cli: cli, askpass: URL(fileURLWithPath: "/path/of/askpass")) { line in
            add.yield((line, false))
        } ended: { worked in
            add.yield((nil, worked))
            add.finish()
        }
        var lines: [String] = [], worked = false
        for await event in events {
            if let line = event.line {
                lines.append(line)
            } else {
                worked = event.worked
            }
        }
        return (lines, worked)
    }
}
