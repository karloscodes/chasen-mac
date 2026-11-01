import ChasenKit
import Foundation
import Observation

/// The login of the panel, in the app and with no terminal.
@MainActor @Observable
final class Signin {
    private(set) var state = LoginState.closed

    /// Called when a login worked.
    @ObservationIgnored var onLogin: () -> Void = {}

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var lines: [String] = []
    @ObservationIgnored private var cancelled = false

    func open() {
        if process == nil {
            state = .open
        }
    }

    func start(_ address: String) {
        guard process == nil else { return }
        lines = []
        cancelled = false
        state = .running([])
        do {
            process = try addServer(address, cli: CLI.url, askpass: CLI.askpass) { [weak self] line in
                Task { @MainActor in self?.heard(line) }
            } ended: { [weak self] worked in
                Task { @MainActor in self?.ended(worked) }
            }
        } catch {
            state = .failed(["Cannot start \(CLI.url.path): \(error.localizedDescription)"])
        }
    }

    /// Stops a login that runs, or closes the form.
    func cancel() {
        guard let process else {
            state = .closed
            return
        }
        cancelled = true
        process.terminate()
    }

    private func heard(_ line: String) {
        guard !line.isEmpty, case .running = state else { return }
        lines = Array((lines + [line]).suffix(6))
        state = .running(lines)
    }

    private func ended(_ worked: Bool) {
        process = nil
        if worked || cancelled {
            state = .closed
        } else {
            state = .failed(lines.isEmpty ? ["chasen add server stopped."] : lines)
        }
        if worked {
            onLogin()
        }
    }
}
