import AppKit
import ChasenKit
import ChasenUI
import Foundation
import Observation
import SwiftUI

/// What the window of the dashboard knows. The overview comes from the Feed,
/// and the rest from commands of the CLI that change nothing: the same as the
/// screen of the CLI asks for. Each command is one process and, through SSH,
/// one login, so the window asks only for what it shows, and only while it is
/// open.
@MainActor @Observable
final class Board {
    var place: Place? {
        didSet {
            guard place != oldValue else { return }
            UserDefaults.standard.set(place?.server, forKey: "dashboard.server")
            UserDefaults.standard.set(place?.app, forKey: "dashboard.app")
            refresh()
        }
    }
    var tab: AppTab = .overview {
        didSet {
            guard tab != oldValue else { return }
            UserDefaults.standard.set(tab.rawValue, forKey: "dashboard.tab")
            refresh()
        }
    }
    var entry: Entry?
    private(set) var loads: [String: ServerLoad] = [:]
    private(set) var facts: [Place: Facts] = [:]

    private let feed: Feed
    @ObservationIgnored private var addresses: [String] = []
    /// The commands that run now, so a slow server does not get a second one.
    @ObservationIgnored private var asking: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var logs: Process?
    @ObservationIgnored private var logsOf: Place?
    @ObservationIgnored private var newLines: [String] = []
    @ObservationIgnored private var flushing = false

    /// The most lines of the logs that the window keeps.
    private static let keep = 5000

    init(feed: Feed) {
        self.feed = feed
        // The window comes back to the app and the tab of the last time.
        let saved = UserDefaults.standard
        if let server = saved.string(forKey: "dashboard.server") {
            place = saved.string(forKey: "dashboard.app").map { .app(server: server, app: $0) } ?? .server(server)
        }
        tab = saved.string(forKey: "dashboard.tab").flatMap(AppTab.init) ?? .overview
    }

    /// The window opens.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.feed.askNow()
                self?.refresh()
            }
        }
        pickFirst()
    }

    /// The window closes: no process stays behind.
    func stop() {
        timer?.invalidate()
        timer = nil
        asking.values.forEach { $0.cancel() }
        asking = [:]
        stopLogs()
    }

    /// With nothing chosen, or a server that is gone, the first server.
    /// The overview can come after the window, so this asks again.
    func pickFirst() {
        guard let servers = feed.overview?.servers, let first = servers.first else { return }
        if !servers.contains(where: { $0.name == place?.server }) {
            place = .server(first.name)
        }
        refresh()
    }

    func refresh() {
        guard timer != nil, let place else { return }
        let server = place.server
        once("load \(server)", place) { ask in
            self.loads[server] = ServerLoad(try await ask.text("load"))
        }
        guard let app = place.app else {
            stopLogs()
            return
        }
        if tab != .logs {
            stopLogs()
        }
        switch tab {
        case .overview:
            once("status \(app)", place) { ask in
                self.facts[place, default: Facts()].status = AppStatus(try await ask.text("status", app: app))
            }
            askHistory(place, app)
        case .history:
            askHistory(place, app)
        case .backups:
            once("backups \(app)", place) { ask in
                self.facts[place, default: Facts()].backups = BackupRow.rows(try await ask.text("backups", app: app))
            }
        case .domains:
            once("domains \(app)", place) { ask in
                self.facts[place, default: Facts()].domains = Report.lines(try await ask.text("domains", app: app))
            }
        case .logs:
            followLogs(place, app)
        }
    }

    /// The output of one row of the history, in a sheet.
    func show(_ row: HistoryRow) {
        guard let place, let app = place.app else { return }
        entry = Entry(id: row.id, title: row.action, command: "history -a \(app) \(row.id)")
        once("entry \(app) \(row.id)", place) { ask in
            let lines = Report.lines(try await ask.text("history", row.id, app: app))
            if self.entry?.id == row.id {
                self.entry?.lines = lines
            }
        }
    }

    private func askHistory(_ place: Place, _ app: String) {
        once("history \(app)", place) { ask in
            self.facts[place, default: Facts()].history = HistoryRow.rows(try await ask.text("history", app: app))
        }
    }

    /// Runs a question, unless the same one runs already.
    private func once(_ key: String, _ place: Place, _ question: @escaping (Ask) async throws -> Void) {
        let key = place.server + " " + key
        guard asking[key] == nil else { return }
        asking[key] = Task {
            do {
                try await question(try await self.ask(place.server))
                self.facts[place, default: Facts()].problem = nil
            } catch let failure as Ask.Failure {
                if !Task.isCancelled {
                    self.facts[place, default: Facts()].problem = failure.message
                }
            } catch {}
            self.asking[key] = nil
        }
    }

    /// The way to one server. `--server` takes the address, and the overview
    /// has the name: `chasen servers` has them in the same order.
    private func ask(_ server: String) async throws -> Ask {
        let servers = feed.overview?.servers ?? []
        if addresses.count != servers.count {
            addresses = Report.addresses(try await Ask(cli: CLI.url, server: "").text("servers"))
        }
        guard addresses.count == servers.count, let index = servers.firstIndex(where: { $0.name == server }) else {
            throw Ask.Failure("Chasen has no address for \(server).")
        }
        return Ask(cli: CLI.url, server: addresses[index])
    }

    private func followLogs(_ place: Place, _ app: String) {
        guard logsOf != place else { return }
        stopLogs()
        logsOf = place
        facts[place, default: Facts()].logs = []
        Task {
            do {
                let ask = try await ask(place.server)
                guard logsOf == place else { return }
                logs = try ask.follow("logs", app: app) { [weak self] line in
                    Task { @MainActor in self?.heard(line, place) }
                } ended: { [weak self] in
                    Task { @MainActor in self?.logsEnded(place) }
                }
            } catch {
                heard("The logs stopped: \((error as? Ask.Failure)?.message ?? error.localizedDescription)", place)
            }
        }
    }

    private func stopLogs() {
        logs?.terminate()
        logs = nil
        logsOf = nil
        newLines = []
    }

    /// A busy app says many lines in a second: they reach the view in groups.
    private func heard(_ line: String, _ place: Place) {
        guard logsOf == place else { return }
        newLines.append(line)
        guard !flushing else { return }
        flushing = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            flushing = false
            guard logsOf == place else { return }
            let lines = (facts[place]?.logs ?? []) + newLines
            facts[place, default: Facts()].logs = Array(lines.suffix(Self.keep))
            newLines = []
        }
    }

    private func logsEnded(_ place: Place) {
        guard logsOf == place else { return }
        heard("The logs stopped.", place)
        logs = nil
        logsOf = nil
    }
}

/// The window of the dashboard: one, made at the first click. While it is open
/// the app is a normal app, with a place in the Dock and in ⌘-Tab, and when it
/// closes the app goes back to the menu bar.
@MainActor
final class DashboardWindow: NSObject, NSWindowDelegate {
    let board: Board
    let feed: Feed
    private var window: NSWindow?

    init(board: Board, feed: Feed) {
        self.board = board
        self.feed = feed
    }

    func show(_ place: Place?) {
        if let place {
            board.place = place
        }
        board.start()
        feed.askNow()
        let window = window ?? make()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window behind the others, with no click and no focus: for a test.
    func showBehind() {
        board.start()
        (window ?? make()).orderBack(nil)
    }

    private func make() -> NSWindow {
        let made = Dashboard.window(DashboardRoot(board: board, feed: feed))
        made.delegate = self
        made.setFrameAutosaveName("Dashboard")
        made.center()
        window = made
        return made
    }

    func windowWillClose(_ notification: Notification) {
        board.stop()
        NSApp.setActivationPolicy(.accessory)
    }
}

struct DashboardRoot: View {
    @Bindable var board: Board
    let feed: Feed

    var body: some View {
        Dashboard(overview: feed.overview, problem: feed.problem, sway: feed.sway, loads: board.loads, facts: board.facts, place: $board.place, tab: $board.tab, entry: $board.entry, actions: DashboardActions(
            open: { NSWorkspace.shared.open($0) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            refresh: {
                feed.askNow()
                board.refresh()
            },
            show: { board.show($0) },
            theme: { theme in
                Look.shared.theme = theme
                try? theme.save()
            }
        ))
        .onChange(of: feed.overview?.servers.map(\.name)) { board.pickFirst() }
    }
}
