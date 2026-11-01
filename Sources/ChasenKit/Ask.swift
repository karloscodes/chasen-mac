import Foundation

/// A question for one server, through the CLI: one process, and one ssh login
/// for a server through SSH. The window asks with the commands that change
/// nothing. A command for a server that needs a person, like a key in
/// 1Password, waits for that person, so the question has no time limit.
public struct Ask: Sendable {
    public struct Failure: Error, Equatable {
        public var message: String

        public init(_ message: String) {
            self.message = message
        }
    }

    public let cli: URL
    public let server: String

    public init(cli: URL, server: String) {
        self.cli = cli
        self.server = server
    }

    /// The output of one command, when it ends.
    public func text(_ words: String..., app: String? = nil) async throws -> String {
        let process = self.process(words, app: app)
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let said = Said()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<String, Error>) in
                // The end of the process, not the end of its output: an ssh that
                // the CLI started can keep the pipes open after the CLI stopped.
                process.terminationHandler = { ended in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                        if ended.terminationStatus == 0 {
                            done.resume(returning: said.output)
                        } else {
                            done.resume(throwing: Failure(said.errors))
                        }
                    }
                }
                do {
                    try process.run()
                    output.fileHandleForReading.readLines { said.add(output: $0) }
                    errors.fileHandleForReading.readLines { said.add(error: $0) }
                    // A cancel before the start found no process to end.
                    if Task.isCancelled {
                        process.terminate()
                    }
                } catch {
                    done.resume(throwing: Failure(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Runs a command that does not end, like `logs`, and gives each clean
    /// line. The caller ends it with `terminate`.
    public func follow(_ words: String..., app: String? = nil, line: @escaping @Sendable (String) -> Void, ended: @escaping @Sendable () -> Void) throws -> Process {
        let process = self.process(words, app: app)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: ended)
        }
        try process.run()
        output.fileHandleForReading.readLines { line(Report.clean($0)) }
        return process
    }

    private func process(_ words: [String], app: String?) -> Process {
        let process = Process()
        process.executableURL = cli
        process.arguments = words + (app.map { ["-a", $0] } ?? []) + ["--server", server]
        // A chasen.yml in the directory of the app must not name another server.
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        var environment = ProcessInfo.processInfo.environment
        environment["CHASEN_NO_UPDATE_CHECK"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        return process
    }
}

/// What a process said on its two pipes, from their two threads.
private final class Said: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var bad: [String] = []

    func add(output line: String) {
        lock.withLock { lines.append(line) }
    }

    func add(error line: String) {
        lock.withLock { bad.append(line) }
    }

    var output: String {
        lock.withLock { lines.map { $0 + "\n" }.joined() }
    }

    var errors: String {
        lock.withLock { bad.joined(separator: "\n") }
    }
}
