import AppKit
import ChasenKit
import SwiftUI

/// What the panel can do. The app gives the real actions, and the snapshots
/// give none.
public struct PanelActions {
    public var open: (URL) -> Void
    public var copy: (String) -> Void
    public var screen: () -> Void
    public var login: (String) -> Void
    public var retry: () -> Void
    public var quit: () -> Void

    public init(open: @escaping (URL) -> Void, copy: @escaping (String) -> Void, screen: @escaping () -> Void, login: @escaping (String) -> Void, retry: @escaping () -> Void, quit: @escaping () -> Void) {
        self.open = open
        self.copy = copy
        self.screen = screen
        self.login = login
        self.retry = retry
        self.quit = quit
    }

    public static let none = PanelActions(open: { _ in }, copy: { _ in }, screen: {}, login: { _ in }, retry: {}, quit: {})
}

/// The panel under the whisk in the menu bar: each server, its apps, and its
/// alerts, like the map of the screen of `chasen`. A click opens an app. The
/// screen in the terminal does the rest: logs, history, rollback.
public struct Panel: View {
    let overview: Overview?
    let problem: String?
    let sway: Double
    let about: String
    @Binding var atLogin: Bool
    let actions: PanelActions
    let now: Date

    public init(overview: Overview?, problem: String?, sway: Double, about: String, atLogin: Binding<Bool>, actions: PanelActions, now: Date = .now) {
        self.overview = overview
        self.problem = problem
        self.sway = sway
        self.about = about
        self._atLogin = atLogin
        self.actions = actions
        self.now = now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(mood: overview?.mood ?? (problem == nil ? .asking : .stopped), sway: sway)
            Rule()
            content
            Rule()
            Footer(about: about, atLogin: $atLogin, actions: actions)
        }
        .frame(width: 400)
        .font(Theme.mono())
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder var content: some View {
        if let overview, overview.servers.isEmpty {
            Login(actions: actions)
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
        // One column of names for every server, so the versions line up.
        let name = min(16, overview.servers.flatMap(\.apps).map(\.app.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(overview.servers) { server in
                ServerSection(server: server, name: name, actions: actions, now: now)
            }
        }
        .padding(.bottom, 8)
    }
}

/// The width of a number of characters of the mono type.
func columns(_ n: Int, size: CGFloat = 12) -> CGFloat {
    CGFloat(n) * NSFont.monospacedSystemFont(ofSize: size, weight: .regular).maximumAdvancement.width
}

struct Rule: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}

struct Header: View {
    let mood: Mood
    let sway: Double

    var body: some View {
        HStack(spacing: 10) {
            MarkView(sway: sway).frame(width: CGFloat(Mark.width) * 1.25, height: CGFloat(Mark.height) * 1.25)
            Text("chasen").font(Theme.mono(13, .semibold))
            Spacer()
            if mood.busy {
                Cursor(width: 6, height: 12)
            }
            Text(mood.line).font(Theme.mono(11)).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    var color: Color {
        switch mood.level {
        case .trouble: Theme.error
        case .warning: Theme.secondary
        case .empty, .calm: mood.busy ? Theme.accent : Theme.dim
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

/// The amber block of a terminal that waits: a change runs.
struct Cursor: View {
    var width: CGFloat = 7
    var height: CGFloat = 13

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let on = Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Rectangle().fill(Theme.accent.opacity(on ? 1 : 0.3)).frame(width: width, height: height)
        }
    }
}

struct ServerSection: View {
    let server: Overview.Server
    /// The width of the column of names, in characters.
    let name: Int
    let actions: PanelActions
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(server.name).font(Theme.mono(11, .semibold)).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer()
                Text(server.error == nil ? counted(server.apps.count, "app", "apps") : "does not answer")
                    .font(Theme.mono(11))
                    .foregroundStyle(server.error == nil ? Theme.dim : Theme.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
            if let error = server.error {
                Text(error)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
            ForEach(server.apps) { app in
                AppRow(app: app, name: name, actions: actions, now: now)
            }
            ForEach(server.alerts) { alert in
                AlertRow(alert: alert)
            }
        }
    }
}

struct AppRow: View {
    let app: Overview.App
    /// The width of the column of names, in characters.
    let name: Int
    let actions: PanelActions
    let now: Date
    @State private var hover = false
    @State private var copied = false

    var body: some View {
        Button(action: click) {
            HStack(spacing: 10) {
                dot.frame(width: 7)
                Text(app.app).frame(width: columns(name), alignment: .leading).lineLimit(1)
                detail
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(hover ? Theme.surface : .clear)
            // The hint covers the end of the row: it takes no room from the address.
            .overlay(alignment: .trailing) {
                if (hover || copied) && !hint.isEmpty {
                    Text(hint)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.secondary)
                        .padding(.leading, 12)
                        .padding(.trailing, 14)
                        .frame(maxHeight: .infinity)
                        .background(Theme.surface)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(app.state)
        .contextMenu {
            if let link = app.link {
                Button("Open \(link.host ?? link.absoluteString)") { actions.open(link) }
                Button("Copy \(link.absoluteString)") { actions.copy(link.absoluteString) }
            }
            if let listen = app.listen {
                Button("Copy http://\(listen)") { actions.copy("http://" + listen) }
            }
            Divider()
            Button("Open the screen") { actions.screen() }
        }
    }

    @ViewBuilder var dot: some View {
        if app.ships {
            Cursor(width: 7, height: 12)
        } else {
            Rectangle().fill(app.up ? Theme.dim : Theme.error).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder var detail: some View {
        if app.ships {
            Text(app.running ?? "").foregroundStyle(Theme.accent).lineLimit(1)
            if let age {
                Text(age).foregroundStyle(Theme.dim).fixedSize()
            }
        } else if !app.up {
            Text("down").foregroundStyle(Theme.error).fixedSize()
            Text(app.state).foregroundStyle(Theme.dim).lineLimit(1)
        } else {
            Text(app.version).foregroundStyle(Theme.secondary).frame(width: columns(9), alignment: .leading).lineLimit(1)
            if let listen = app.listen {
                Text("private").foregroundStyle(Theme.dim).fixedSize()
                Text(listen).foregroundStyle(Theme.secondary).lineLimit(1)
            } else if let domain = app.domains?.first {
                Text(domain).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    var hint: String {
        if copied { return "copied" }
        if app.link != nil { return "open ↗" }
        return app.listen != nil ? "copy" : ""
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("!").font(Theme.mono(12, .bold)).foregroundStyle(alert.error ? Theme.error : Theme.secondary).frame(width: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.what).foregroundStyle(alert.error ? Theme.error : Theme.text)
                if !alert.fix.isEmpty {
                    Text(alert.fix).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct Login: View {
    let actions: PanelActions
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No server yet.")
            Text("Log in to your server through SSH, or through its address on the web.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("root@203.0.113.5", text: $address)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(8)
                .background(Theme.surface)
                .overlay(Rectangle().stroke(Theme.line))
                .onSubmit(login)
            Button(action: login) {
                Text("$ chasen add server \(server.isEmpty ? "<server>" : server)")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.background)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(server.isEmpty ? 0.5 : 1))
            }
            .buttonStyle(.plain)
            .disabled(server.isEmpty)
            Button {
                actions.open(URL(string: "https://chasenhq.com/docs/getting-started/")!)
            } label: {
                Text("New to Chasen? Get started ↗").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    var server: String { address.trimmingCharacters(in: .whitespaces) }

    func login() {
        if !server.isEmpty {
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
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            FooterButton(title: "try again", key: "", action: retry)
        }
        .padding(14)
    }
}

/// Before the first answer: the command that asks, and the cursor.
struct Waiting: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("$ chasen overview --watch").foregroundStyle(Theme.dim)
            Cursor()
        }
        .padding(14)
    }
}

struct Footer: View {
    let about: String
    @Binding var atLogin: Bool
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                FooterButton(title: "open the screen", key: "⌘O", action: actions.screen).keyboardShortcut("o")
                Spacer()
                FooterButton(title: "quit", key: "⌘Q", action: actions.quit).keyboardShortcut("q")
            }
            HStack {
                FooterButton(title: (atLogin ? "[x]" : "[ ]") + " open at login", key: "") { atLogin.toggle() }
                Spacer()
                Text(about).font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct FooterButton: View {
    let title: String
    let key: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).foregroundStyle(hover ? Theme.text : Theme.secondary)
                if !key.isEmpty {
                    Text(key).foregroundStyle(Theme.dim)
                }
            }
            .font(Theme.mono(11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
