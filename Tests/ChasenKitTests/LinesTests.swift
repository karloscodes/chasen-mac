import Foundation
import Testing
@testable import ChasenKit

@Suite("The lines of a pipe")
struct LinesTests {
    @Test("come one by one while the other pipe stays silent")
    func comeWhileTheOtherPipeIsSilent() async throws {
        let shell = Shell("echo one; read a; echo two; read a")

        #expect(await shell.nextLine() == "one")
        shell.goOn()

        #expect(await shell.nextLine() == "two")
        shell.goOn()
    }

    @Test("wait for the end of a line that comes in two parts")
    func waitForTheEndOfALine() async throws {
        let shell = Shell("printf 'par'; read a; printf 'tial\\nlast'")

        shell.goOn()

        #expect(await shell.nextLine() == "partial")
        #expect(await shell.nextLine() == "last")
    }
}

@Suite("What a process said")
struct SaidTests {
    @Test("keeps the last five lines")
    func keepsTheLastFive() {
        let said = ["1", "2", "3", "4", "5", "6"].reduce([String]()) { $0.hearing($1) }

        #expect(said == ["2", "3", "4", "5", "6"])
    }

    @Test("keeps one copy of a line that ssh says again at each ask")
    func keepsOneCopy() {
        let said = ["denied", "closed", "denied", "closed", "denied"].reduce([String]()) { $0.hearing($1) }

        #expect(said == ["closed", "denied"])
    }

    @Test("skips an empty line")
    func skipsAnEmptyLine() {
        #expect(["denied"].hearing("") == ["denied"])
    }
}

/// A real shell with three pipes, the same as the app and its CLI. It stops
/// at each `read` until `goOn`. Five seconds with no line end the test.
final class Shell {
    private let process = Process()
    private let input = Pipe()
    private var lines: AsyncStream<String>.Iterator

    init(_ script: String) {
        let output = Pipe(), errors = Pipe()
        let (stream, add) = AsyncStream.makeStream(of: String.self)
        lines = stream.makeAsyncIterator()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readLines { add.yield($0) }
        errors.fileHandleForReading.readLines { add.yield("stderr: " + $0) }
        try! process.run()
        Task {
            try? await Task.sleep(for: .seconds(5))
            add.finish()
        }
    }

    func nextLine() async -> String? {
        await lines.next()
    }

    func goOn() {
        input.fileHandleForWriting.write(Data("\n".utf8))
    }

    deinit {
        process.terminate()
    }
}
