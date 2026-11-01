import AppKit
import ChasenKit
import SwiftUI

/// What the panel can do. The app gives the real actions, and the snapshots
/// give none.
public struct PanelActions {
    public var open: (URL) -> Void
    public var copy: (String) -> Void
    public var addServer: () -> Void
    public var login: (String) -> Void
    public var cancelLogin: () -> Void
    public var retry: () -> Void
    public var quit: () -> Void
    /// Opens the window of the dashboard on a server or an app, or as it was.
    public var dashboard: (Place?) -> Void

    public init(open: @escaping (URL) -> Void, copy: @escaping (String) -> Void, addServer: @escaping () -> Void, login: @escaping (String) -> Void, cancelLogin: @escaping () -> Void, retry: @escaping () -> Void, quit: @escaping () -> Void, dashboard: @escaping (Place?) -> Void) {
        self.open = open
        self.copy = copy
        self.addServer = addServer
        self.login = login
        self.cancelLogin = cancelLogin
        self.retry = retry
        self.quit = quit
        self.dashboard = dashboard
    }

    public static let none = PanelActions(open: { _ in }, copy: { _ in }, addServer: {}, login: { _ in }, cancelLogin: {}, retry: {}, quit: {}, dashboard: { _ in })
}

/// The panel under the whisk in the menu bar: each server, its apps, and its
/// alerts. A click opens the dashboard. The window of the menu bar has the material
/// of macOS: the panel draws on it, and paints no background of its own.
public struct Panel: View {
    let overview: Overview?
    let problem: String?
    let sway: Double
    let login: LoginState
    /// What ssh said about a server that does not answer.
    let said: [String]
    let about: String
    @Binding var atLogin: Bool
    let actions: PanelActions
    let now: Date

    public init(overview: Overview?, problem: String?, sway: Double, login: LoginState = .closed, said: [String] = [], about: String, atLogin: Binding<Bool>, actions: PanelActions, now: Date = .now) {
        self.overview = overview
        self.problem = problem
        self.sway = sway
        self.login = login
        self.said = said
        self.about = about
        self._atLogin = atLogin
        self.actions = actions
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(mood: overview?.mood ?? (problem == nil ? .asking : .stopped), sway: sway, about: about)
            content
            Divider().padding(.horizontal, 14)
            Footer(canOpen: loggedIn, canAdd: loggedIn && login == .closed, atLogin: $atLogin, actions: actions)
        }
        .frame(width: 420)
    }

    var loggedIn: Bool { overview?.servers.isEmpty == false }

    @ViewBuilder var content: some View {
        if login != .closed || overview?.servers.isEmpty == true {
            Login(state: login, canCancel: loggedIn, actions: actions)
        } else if let overview {
            // A short list has no scroll bar. A long one scrolls in a fixed height.
            let rows = overview.servers.reduce(0) { $0 + 1 + $1.apps.count + 2 * $1.alerts.count }
            if rows <= 18 {
                servers(overview)
            } else {
                ScrollView { servers(overview) }.frame(height: 520)
            }
        } else if let problem {
            Problem(text: problem, retry: actions.retry)
        } else {
            Waiting()
        }
    }

    func servers(_ overview: Overview) -> some View {
        // One column of names and one of versions for every server, so they line up.
        let apps = overview.servers.flatMap(\.apps)
        let name = min(16, apps.map(\.app.count).max() ?? 0)
        let version = min(11, max(6, apps.map(\.version.count).max() ?? 0))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(overview.servers) { server in
                ServerSection(server: server, name: name, version: version, actions: actions, now: now)
            }
            ForEach(said, id: \.self) { line in
                Text(line)
                    .font(Theme.mono(11))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 8)
    }
}

/// The width of a number of characters of the mono type.
func columns(_ n: Int, size: CGFloat = 12) -> CGFloat {
    CGFloat(n) * NSFont.monospacedSystemFont(ofSize: size, weight: .regular).maximumAdvancement.width
}

struct Header: View {
    let mood: Mood
    let sway: Double
    let about: String

    var body: some View {
        HStack(spacing: 8) {
            MarkView(sway: sway).frame(width: CGFloat(Mark.width) * 1.1, height: CGFloat(Mark.height) * 1.1)
            Text("Chasen").font(.system(size: 13, weight: .semibold)).help(about)
            Spacer()
            if mood.busy {
                Pulse()
            }
            Text(mood.line).font(.system(size: 12)).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    var color: Color {
        switch mood.level {
        case .trouble: Theme.error
        case .empty, .warning, .calm: mood.busy ? .primary : .secondary
        }
    }
}

/// The whisk, drawn from its cells.
public struct MarkView: View {
    var sway: Double
    var color: Color

    public init(sway: Double = 0, color: Color = Theme.accent) {
        self.sway = sway
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            let cell = min(size.width / CGFloat(Mark.width), size.height / CGFloat(Mark.height))
            for c in Mark.cells(sway: sway) {
                context.fill(Path(CGRect(x: (c.x + Mark.left) * cell, y: CGFloat(c.y) * cell, width: cell, height: cell)), with: .color(color))
            }
        }
    }
}

/// The amber dot that beats: a change runs.
struct Pulse: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let on = Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Circle().fill(Theme.accent.opacity(on ? 1 : 0.3)).frame(width: 7, height: 7)
        }
    }
}

/// The state of an app. With no color in the theme, a hollow dot is an app
/// that is down.
struct Dot: View {
    let up: Bool

    var body: some View {
        Group {
            if !up && Look.shared.noColor {
                Circle().strokeBorder(Color.primary, lineWidth: 1.5)
            } else {
                Circle().fill(up ? Theme.accent : Theme.error)
            }
        }
        .frame(width: 7, height: 7)
    }
}

/// The highlight of a row under the pointer, like a row of Control Center.
struct Highlight: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(on ? 0.1 : 0))
    }
}

struct ServerSection: View {
    let server: Overview.Server
    /// The width of the column of names, in characters.
    let name: Int
    /// The width of the column of versions, in characters.
    let version: Int
    let actions: PanelActions
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(server.name) { actions.dashboard(.server(server.name)) }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .help("Open the map of \(server.name)")
                Spacer()
                if server.error != nil {
                    Text("Does not answer")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
            if let error = server.error {
                Text(server.advice ?? error)
                    .font(server.advice == nil ? Theme.mono(11) : .system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(error)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            ForEach(server.apps) { app in
                AppRow(app: app, server: server.name, name: name, version: version, actions: actions, now: now)
            }
            ForEach(server.alerts) { alert in
                AlertRow(alert: alert)
            }
        }
    }
}

/// A click opens the app in the dashboard. Under the pointer, the arrow at the
/// end opens its site, or copies the address of a private app.
struct AppRow: View {
    let app: Overview.App
    let server: String
    /// The width of the column of names, in characters.
    let name: Int
    /// The width of the column of versions, in characters.
    let version: Int
    let actions: PanelActions
    let now: Date
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Button { actions.dashboard(.app(server: server, app: app.app)) } label: {
                HStack(spacing: 10) {
                    dot.frame(width: 7)
                    Text(app.app)
                        .font(Theme.mono(12, .medium))
                        .frame(width: columns(name), alignment: .leading)
                        .lineLimit(1)
                    detail.frame(maxWidth: .infinity, alignment: .leading)
                    Text(last)
                        .font(Theme.mono(11))
                        .foregroundStyle(.secondary)
                        .frame(width: columns(version, size: 11), alignment: .leading)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: click) {
                Image(systemName: app.link == nil ? "doc.on.doc" : "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hover && app.address != nil ? 1 : 0)
            .help(app.link == nil ? "Copy the address" : "Open the site")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Highlight(on: hover))
        .padding(.horizontal, 6)
        .onHover { hover = $0 }
        .help(app.state)
        .contextMenu {
            Button("Open in Dashboard") { actions.dashboard(.app(server: server, app: app.app)) }
            if let link = app.link {
                Button("Open \(link.host ?? link.absoluteString)") { actions.open(link) }
                Button("Copy \(link.absoluteString)") { actions.copy(link.absoluteString) }
            }
            if let listen = app.listen {
                Button("Copy http://\(listen)") { actions.copy("http://" + listen) }
            }
        }
    }

    @ViewBuilder var dot: some View {
        if app.ships {
            Pulse()
        } else {
            Dot(up: app.up)
        }
    }

    @ViewBuilder var detail: some View {
        if app.ships {
            Text(app.running ?? "").font(Theme.mono(11)).lineLimit(1)
        } else if !app.up {
            HStack(spacing: 8) {
                Text("down").foregroundStyle(Theme.error).fixedSize()
                Text(app.state).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(Theme.mono(11))
        } else {
            Text(app.domain ?? app.listen ?? "")
                .font(Theme.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The last column: the version, or how long the change runs.
    var last: String {
        if copied { return "Copied" }
        return app.ships ? (age ?? "") : app.version
    }

    /// How long the change runs, from the clock of the server.
    var age: String? {
        guard let since = app.since, let start = ISO8601DateFormatter().date(from: since) else { return nil }
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : "\(s / 3600)h"
    }

    func click() {
        if let link = app.link {
            actions.open(link)
        } else if let listen = app.listen {
            actions.copy("http://" + listen)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }
}

struct AlertRow: View {
    let alert: Overview.Alert

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: alert.error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(alert.error ? Theme.error : Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.what).font(.system(size: 12))
                if !alert.fix.isEmpty {
                    Text(alert.fix).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// The form of a login, and what the login says while it runs. No terminal:
/// the CLI runs behind it, and ssh asks its questions in dialogs of macOS.
struct Login: View {
    let state: LoginState
    /// The panel has servers to go back to.
    let canCancel: Bool
    let actions: PanelActions
    @State private var address = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Server").font(.system(size: 13, weight: .semibold))
                Text("Use SSH, or the address of your server on the web.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("root@203.0.113.5", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(12))
                .focused($focused)
                .disabled(running)
                .onSubmit(login)
            output
            HStack {
                Button {
                    actions.open(URL(string: "https://chasenhq.com/docs/getting-started/")!)
                } label: {
                    Text("New to Chasen?").font(.system(size: 12))
                }
                .buttonStyle(.link)
                Spacer()
                if running || canCancel {
                    Button("Cancel", action: actions.cancelLogin).keyboardShortcut(.cancelAction)
                }
                Button("Log In", action: login)
                    .keyboardShortcut(.defaultAction)
                    .disabled(running || server.isEmpty)
            }
        }
        .padding(14)
        .onAppear { focused = true }
    }

    /// What `chasen add server` says, in the type of the machine.
    @ViewBuilder var output: some View {
        switch state {
        case let .running(lines):
            if !lines.isEmpty {
                lastLines(lines, color: .secondary)
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Logging in").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case let .failed(lines):
            lastLines(lines, color: Theme.error)
        case .closed, .open:
            EmptyView()
        }
    }

    func lastLines(_ lines: [String], color: Color) -> some View {
        Text(lines.joined(separator: "\n"))
            .font(Theme.mono(11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    var running: Bool {
        if case .running = state { return true }
        return false
    }

    var server: String { address.trimmingCharacters(in: .whitespaces) }

    func login() {
        if !server.isEmpty && !running {
            actions.login(server)
        }
    }
}

struct Problem: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button("Try Again", action: retry)
        }
        .padding(14)
    }
}

/// Before the first answer of the servers.
struct Waiting: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Asking your servers").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

struct Footer: View {
    /// A server to show.
    let canOpen: Bool
    /// The form of a login is not open, so a new one can start.
    let canAdd: Bool
    @Binding var atLogin: Bool
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            if canOpen {
                MenuRow(title: "Open Dashboard", key: "⌘D") { actions.dashboard(nil) }.keyboardShortcut("d")
            }
            if canAdd {
                MenuRow(title: "Add Server…", key: "⌘N", action: actions.addServer).keyboardShortcut("n")
            }
            MenuRow(title: "Open at Login", checked: atLogin) { atLogin.toggle() }
            MenuRow(title: "Quit Chasen", key: "⌘Q", action: actions.quit).keyboardShortcut("q")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

/// A row at the end of the panel, like an item of a menu.
struct MenuRow: View {
    let title: String
    var key = ""
    var checked = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Spacer()
                if checked {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text(key).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(Highlight(on: hover))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
