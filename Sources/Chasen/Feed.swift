import ChasenKit
import Foundation
import Observation

/// The overview of your servers, as it comes. One `chasen overview --watch`
/// runs for as long as the app runs, like the bar of Omarchy: it keeps one
/// connection to each server, asks once a minute, and every 5 seconds while
/// a change runs. The CLI has the logins, so the app holds no token.
@MainActor @Observable
final class Feed {
    private(set) var overview: Overview?
    /// What the CLI said when it stopped, or nil.
    private(set) var problem: String?
    /// The whisk, from -1 to 1, while a change ships.
    private(set) var sway = 0.0
    /// The last lines of stderr: why the CLI stopped, or what ssh said about a
    /// server that does not answer. The overview does not have those words.
    private(set) var said: [String] = []

    var mood: Mood { overview?.mood ?? (problem == nil ? .asking : .stopped) }

    /// Called with the news of each new overview.
    @ObservationIgnored var onNews: ([News]) -> Void = { _ in }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var motion: Timer?
    @ObservationIgnored private var stopping = false

    func start() {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = CLI.url
        process.arguments = ["overview", "--watch"]
        var environment = ProcessInfo.processInfo.environment
        environment["CHASEN_NO_UPDATE_CHECK"] = "1"
        process.environment = environment
        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input
        // The end of the process, not the end of its output: an ssh that the
        // CLI started can keep the pipes open after the CLI stopped.
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                // The last line of stderr can come a moment after the end.
                try? await Task.sleep(for: .milliseconds(300))
                self?.ended()
            }
        }
        do {
            try process.run()
        } catch {
            problem = "Cannot start \(CLI.url.path): \(error.localizedDescription)"
            return
        }
        self.process = process
        self.input = input.fileHandleForWriting
        said = []

        output.fileHandleForReading.readLines { [weak self] line in
            guard let overview = Overview.line(line) else { return }
            Task { @MainActor in self?.receive(overview) }
        }
        errors.fileHandleForReading.readLines { [weak self] line in
            Task { @MainActor in self?.heard(line) }
        }
    }

    /// Asks the servers now, not at the next minute: the panel opens.
    func askNow() {
        try? input?.write(contentsOf: Data("\n".utf8))
    }

    /// A login worked: the list is old, so the panel waits for a new one.
    func reload() {
        overview = nil
        askNow()
    }

    func stop() {
        stopping = true
        process?.terminate()
    }

    private func receive(_ new: Overview) {
        problem = nil
        if new.servers.allSatisfy({ $0.error == nil }) {
            said = []
        }
        if let old = overview {
            onNews(new.news(since: old))
        }
        overview = new
        whisk(new.mood.busy)
    }

    private func heard(_ line: String) {
        said = said.hearing(line)
    }

    private func ended() {
        process = nil
        input = nil
        guard !stopping else { return }
        problem = said.isEmpty ? "chasen overview --watch stopped." : said.joined(separator: "\n")
        overview = nil
        whisk(false)
        // A new start, after a pause: a CLI that stops at once does not spin.
        Task {
            try? await Task.sleep(for: .seconds(10))
            start()
        }
    }

    private func whisk(_ busy: Bool) {
        if busy, motion == nil {
            var frame = 0
            motion = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    frame += 1
                    self?.sway = sin(Double(frame) * .pi / 4)
                }
            }
        } else if !busy, let motion {
            motion.invalidate()
            self.motion = nil
            sway = 0
        }
    }
}

/// The chasen CLI that the app runs: the one inside the app, or CHASEN_CLI
/// for a build outside of it (swift run).
enum CLI {
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["CHASEN_CLI"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/chasen")
    }

    /// What ssh runs for a question during a login: bin/askpass.
    static var askpass: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/askpass")
    }
}
