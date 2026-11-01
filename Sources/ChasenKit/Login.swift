import Foundation

/// The login in the panel.
public enum LoginState: Equatable, Sendable {
    /// No form: the panel shows the servers.
    case closed
    case open
    /// `chasen add server` runs, with what it said so far.
    case running([String])
    /// It stopped with an error, and these are its last lines.
    case failed([String])
}

/// Runs `chasen add server`, with no terminal. The CLI saves the login in the
/// file that every chasen of this Mac reads, so the overview finds it too.
/// ssh asks its questions through `askpass`: a new host key, a password, or a
/// passphrase. `ended` gets true when the login worked.
public func addServer(_ address: String, cli: URL, askpass: URL, line: @escaping @Sendable (String) -> Void, ended: @escaping @Sendable (Bool) -> Void) throws -> Process {
    let process = Process()
    process.executableURL = cli
    process.arguments = ["add", "server", address]
    var environment = ProcessInfo.processInfo.environment
    environment["CHASEN_NO_UPDATE_CHECK"] = "1"
    environment["SSH_ASKPASS"] = askpass.path
    environment["SSH_ASKPASS_REQUIRE"] = "force"
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    process.standardInput = FileHandle.nullDevice
    process.terminationHandler = { done in
        let worked = done.terminationReason == .exit && done.terminationStatus == 0
        // The last line can come a moment after the end.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { ended(worked) }
    }
    try process.run()
    output.fileHandleForReading.readLines(line)
    return process
}
