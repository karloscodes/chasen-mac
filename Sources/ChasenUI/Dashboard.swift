import AppKit
import ChasenKit
import SwiftUI

/// What the window can do. The app gives the real actions, and the snapshots
/// give none. Nothing here changes a server: restart, rollback, and restore
/// stay in the CLI.
public struct DashboardActions {
    public var open: (URL) -> Void
    public var copy: (String) -> Void
    public var refresh: () -> Void
    public var show: (HistoryRow) -> Void
    public var theme: (ScreenTheme) -> Void

    public init(open: @escaping (URL) -> Void, copy: @escaping (String) -> Void, refresh: @escaping () -> Void, show: @escaping (HistoryRow) -> Void, theme: @escaping (ScreenTheme) -> Void) {
        self.open = open
        self.copy = copy
        self.refresh = refresh
        self.show = show
        self.theme = theme
    }

    public static let none = DashboardActions(open: { _ in }, copy: { _ in }, refresh: {}, show: { _ in }, theme: { _ in })
}

/// The window of Chasen: the screen of the CLI as a window of macOS. The
/// servers and their apps in the sidebar, and on the right the map of a server
/// or the tabs of an app. It has the same words, the same amber, and the same
/// lines, on the sidebar and the toolbar of the system.
public struct Dashboard: View {
    let overview: Overview?
    let problem: String?
    let sway: Double
    let loads: [String: ServerLoad]
    let facts: [Place: Facts]
    @Binding var place: Place?
    @Binding var tab: AppTab
    @Binding var entry: Entry?
    let actions: DashboardActions
    let now: Date
    @State private var filter = ""
    @State private var follow = true

    public init(overview: Overview?, problem: String?, sway: Double, loads: [String: ServerLoad], facts: [Place: Facts], place: Binding<Place?>, tab: Binding<AppTab>, entry: Binding<Entry?>, actions: DashboardActions, now: Date = .now) {
        self.overview = overview
        self.problem = problem
        self.sway = sway
        self.loads = loads
        self.facts = facts
        self._place = place
        self._tab = tab
        self._entry = entry
        self.actions = actions
        self.now = now
    }

    var server: Overview.Server? {
        overview?.servers.first { $0.name == place?.server }
    }

    var app: Overview.App? {
        server?.apps.first { $0.app == place?.app }
    }

    var load: ServerLoad? {
        place.flatMap { loads[$0.server] }
    }

    public var body: some View {
        NavigationSplitView {
            Sidebar(servers: overview?.servers ?? [], load: load, sway: sway, place: $place)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            detail.toolbar { toolbar }
        }
        .background(WindowTitle(title: app?.app ?? server?.name ?? "Chasen"))
        .navigationSubtitle(app == nil ? (overview?.mood.line ?? "") : (server?.name ?? ""))
        .tint(Theme.accent)
        .frame(minWidth: 820, minHeight: 520)
        .sheet(item: $entry) { entry in
            EntrySheet(entry: entry) { self.entry = nil }
        }
        .background { keys }
    }

    @ViewBuilder var detail: some View {
        if let server, let app {
            let facts = facts[Place.app(server: server.name, app: app.app)] ?? Facts()
            AppPage(app: app, server: server.name, tab: tab, facts: facts, filter: $filter, follow: follow, actions: actions, now: now)
        } else if let server {
            ServerPage(server: server, load: load, place: $place, now: now)
        } else if let problem {
            Note(title: "Chasen stopped", text: problem)
        } else {
            Asking(what: "your servers")
        }
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        if app != nil {
            ToolbarItem(placement: .principal) {
                Picker("Part of the app", selection: $tab) {
                    ForEach(AppTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Spacer()
            if app != nil, tab == .logs {
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .help("Stay at the end of the logs")
            }
            if let link = app?.link {
                Button { actions.open(link) } label: {
                    Label("Open Site", systemImage: "arrow.up.right")
                }
                .help("Open \(link.host ?? link.absoluteString)")
            }
            Menu {
                Picker("Theme", selection: Binding(get: { Look.shared.theme }, set: actions.theme)) {
                    ForEach(ScreenTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .help("The theme, the same as t on the screen of the CLI")
            Button(action: actions.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Ask the server again")
        }
    }

    /// ⌘1 to ⌘5 choose a tab, ⌘T goes to the next theme, like t on the screen,
    /// and ⌘W closes the window: the app has no menu of its own, because it
    /// lives in the menu bar.
    var keys: some View {
        ZStack {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, each in
                Button(each.title) { tab = each }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Button("Next Theme") { actions.theme(Look.shared.theme.next) }
                .keyboardShortcut("t")
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// The window around a dashboard, for the app and for the snapshots.
    @MainActor
    public static func window(_ content: some View) -> NSWindow {
        let host = NSHostingController(rootView: content)
        host.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1120, height: 720))
        return window
    }
}

/// The title of the window. A window that AppKit made gets the subtitle from
/// SwiftUI, and not the title.
struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = title }
    }
}

// MARK: - The sidebar

struct Sidebar: View {
    let servers: [Overview.Server]
    let load: ServerLoad?
    let sway: Double
    @Binding var place: Place?

    var body: some View {
        List(selection: $place) {
            Section(servers.count == 1 ? "Server" : "Servers") {
                ForEach(servers) { server in
                    ServerLabel(server: server).tag(Place.server(server.name))
                    ForEach(server.apps) { app in
                        AppLabel(app: app).tag(Place.app(server: server.name, app: app.app))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Corner(load: load, sway: sway)
        }
    }
}

struct ServerLabel: View {
    let server: Overview.Server

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "server.rack")
                .font(.system(size: 11))
                .foregroundStyle(server.error == nil ? Color.secondary : Theme.error)
            Text(server.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if !server.alerts.isEmpty {
                Text("\(server.alerts.count)")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(server.alerts.contains(where: \.error) ? Theme.error : Theme.accent)
            }
        }
    }
}

struct AppLabel: View {
    let app: Overview.App

    var body: some View {
        HStack(spacing: 7) {
            if app.ships {
                Pulse()
            } else {
                Dot(up: app.up)
            }
            Text(app.app).font(Theme.mono(12)).lineLimit(1)
            Spacer(minLength: 4)
            Text(Map.short(app.version))
                .font(Theme.mono(10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 12)
        .help(app.state)
    }
}

/// The corner under the servers, like the screen of the CLI: how busy the
/// server is, and the whisk, which moves while a change ships.
struct Corner: View {
    let load: ServerLoad?
    let sway: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let load, !load.gauges.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(load.gauges) { GaugeLine(gauge: $0) }
                }
            }
            HStack(spacing: 8) {
                MarkView(sway: sway).frame(width: CGFloat(Mark.width), height: CGFloat(Mark.height))
                Text(load?.hardware ?? "")
                    .font(Theme.mono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// `load ━━━━────── 0.42`: the gauge of the screen, in the same characters.
struct GaugeLine: View {
    let gauge: ServerLoad.Gauge
    static let width = 16

    var body: some View {
        let filled = max(gauge.used > 0 ? 1 : 0, min(gauge.used * Self.width / 100, Self.width))
        let parts = [
            Cell(Map.fit(gauge.label, 5), .dim),
            Cell(String(repeating: "━", count: filled), gauge.bad ? .bad : .accent),
            Cell(String(repeating: "─", count: Self.width - filled), .dim),
            Cell(" " + gauge.value),
        ]
        Text(cells: parts).font(Theme.mono(10)).lineLimit(1)
    }
}

extension Text {
    /// The cells of a line, each in its color. With no color in the theme, the
    /// accent is bold, and what is bad is bold and underlined, like the CLI.
    init(cells: [Cell]) {
        let noColor = Look.shared.noColor
        self = cells.reduce(Text(verbatim: "")) { line, cell in
            var part = Text(verbatim: cell.text).foregroundStyle(cell.tone.color)
            if noColor && cell.tone == .bad {
                return line + Text(bad: cell.text)
            }
            if cell.tone == .bold || (noColor && cell.tone == .accent) {
                part = part.fontWeight(.semibold)
            }
            return line + part
        }
    }

    /// Words under a line, with no line under the spaces that fill a column,
    /// or over a line of the map.
    private init(bad text: String) {
        let word = text.replacing(#/\s+$/#, with: "")
        guard word.contains(where: \.isLetter) else {
            self = Text(verbatim: text).fontWeight(.semibold)
            return
        }
        self = Text(verbatim: word).fontWeight(.semibold).underline() + Text(verbatim: String(text.dropFirst(word.count)))
    }
}

extension Cell.Tone {
    var color: Color {
        switch self {
        case .plain, .bold: .primary
        case .dim: .secondary
        case .accent: Theme.accent
        case .bad: Theme.error
        }
    }
}

// MARK: - A server

/// The map of a server, with what puts it at risk under it.
struct ServerPage: View {
    let server: Overview.Server
    let load: ServerLoad?
    @Binding var place: Place?
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        GeometryReader { window in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    title
                    if let error = server.error {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Does not answer").font(.system(size: 12, weight: .semibold))
                            Text(server.advice ?? error).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } else if server.apps.isEmpty {
                        Text("No apps yet. In the directory of an app, run: chasen deploy")
                            .font(Theme.mono(12))
                            .foregroundStyle(.secondary)
                    } else {
                        map(width: window.size.width - 48)
                        Text("A moving line is an open path, or data on its way. It does not count requests.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    if !server.alerts.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alerts").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(server.alerts) { AlertRow(alert: $0).padding(.leading, -14) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
    }

    var title: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(server.name).font(Theme.mono(20, .semibold))
            Text(load?.hardware ?? "").font(Theme.mono(11)).foregroundStyle(.secondary)
            Spacer()
            Text("$ chasen overview").font(Theme.mono(11)).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    func map(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: still)) { timeline in
            let frame = still ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate / 0.12)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Map.lines(of: server, load: load, width: Int(width / columns(1)), frame: frame, now: now)) { line in
                    MapRow(line: line) { place = .app(server: server.name, app: $0) }
                }
            }
        }
    }
}

/// A line of the map. A click on the line of an app chooses the app.
struct MapRow: View {
    let line: MapLine
    let choose: (String) -> Void
    @State private var hover = false

    var body: some View {
        Text(cells: line.cells)
            .font(Theme.mono(12))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 19)
            .padding(.horizontal, 6)
            .background(Highlight(on: hover && line.app != nil))
            .contentShape(Rectangle())
            .padding(.horizontal, -6)
            .onHover { hover = $0 }
            .onTapGesture {
                if let app = line.app {
                    choose(app)
                }
            }
            .accessibilityAddTraits(line.app == nil ? [] : .isButton)
    }
}

// MARK: - An app

struct AppPage: View {
    let app: Overview.App
    let server: String
    let tab: AppTab
    let facts: Facts
    @Binding var filter: String
    let follow: Bool
    let actions: DashboardActions
    let now: Date

    var body: some View {
        switch tab {
        case .overview:
            if let status = facts.status {
                OverviewPage(app: app, status: status, history: facts.history ?? [], actions: actions, now: now)
            } else {
                waiting
            }
        case .history:
            if let rows = facts.history {
                HistoryPage(rows: rows, actions: actions, now: now)
            } else {
                waiting
            }
        case .backups:
            if let rows = facts.backups {
                BackupsPage(rows: rows, now: now)
            } else {
                waiting
            }
        case .domains:
            if let domains = facts.domains {
                DomainsPage(domains: domains, actions: actions)
            } else {
                waiting
            }
        case .logs:
            LogsPage(lines: facts.logs, filter: $filter, follow: follow)
        }
    }

    @ViewBuilder var waiting: some View {
        if let problem = facts.problem {
            Note(title: "\(server) did not answer", text: problem)
        } else {
            Asking(what: server)
        }
    }
}

struct OverviewPage: View {
    let app: Overview.App
    let status: AppStatus
    let history: [HistoryRow]
    let actions: DashboardActions
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.app).font(Theme.mono(20, .semibold))
                    Spacer()
                    Text(cells: [Cell("● ", app.up ? .accent : .bad), Cell(status.state)])
                        .font(Theme.mono(12))
                        .textSelection(.enabled)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                    ForEach(status.fields(now: now)) { field in
                        GridRow {
                            Text(field.name).foregroundStyle(.secondary)
                            value(field)
                        }
                    }
                }
                .font(Theme.mono(12))
                if let running = app.running {
                    Text(cells: [Cell("Running now: ", .dim), Cell(running, .accent)]).font(Theme.mono(12))
                }
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last changes").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(history.prefix(5)) { row in
                            ChangeRow(row: row, now: now) { actions.show(row) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    @ViewBuilder func value(_ field: AppStatus.Field) -> some View {
        if field.name == "URL", let link = URL(string: field.value) {
            Button(field.value) { actions.open(link) }
                .buttonStyle(.link)
                .contextMenu {
                    Button("Copy \(field.value)") { actions.copy(field.value) }
                }
        } else {
            Text(field.value).textSelection(.enabled)
        }
    }
}

/// One change in the overview of an app. A click shows its output.
struct ChangeRow: View {
    let row: HistoryRow
    let now: Date
    let show: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: show) {
            HStack(spacing: 14) {
                Text(row.id).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                Text(row.when(now: now)).foregroundStyle(.secondary).frame(width: 190, alignment: .leading).lineLimit(1)
                Text(row.action).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ResultText(row: row)
            }
            .font(Theme.mono(11))
            .frame(height: 22)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(Highlight(on: hover))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { hover = $0 }
    }
}

/// `✓ succeeded`, `✗ failed`, or `running`, in the marks of the screen.
struct ResultText: View {
    let row: HistoryRow

    var body: some View {
        switch row.outcome {
        case .worked: Text(cells: [Cell("✓ ", .accent), Cell(row.result, .dim)])
        case .failed: Text(cells: [Cell("✗ failed", .bad)])
        case .running: Text(cells: [Cell("● running", .accent)])
        }
    }
}

struct HistoryPage: View {
    let rows: [HistoryRow]
    let actions: DashboardActions
    let now: Date
    @State private var chosen: HistoryRow.ID?

    var body: some View {
        Table(rows, selection: $chosen) {
            TableColumn("ID") { Text($0.id).font(Theme.mono(11)).foregroundStyle(.secondary) }.width(44)
            TableColumn("When (UTC)") { Text($0.when(now: now)).font(Theme.mono(11)).foregroundStyle(.secondary) }.width(min: 120, ideal: 200)
            TableColumn("Action") { Text($0.action).font(Theme.mono(11)) }.width(min: 160, ideal: 340)
            TableColumn("Result") { ResultText(row: $0).font(Theme.mono(11)) }.width(min: 90, ideal: 110)
            TableColumn("Took") { Text($0.took).font(Theme.mono(11)).foregroundStyle(.secondary) }.width(min: 50, ideal: 64)
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: HistoryRow.ID.self) { ids in
            if let row = row(ids) {
                Button("Show Output") { actions.show(row) }
            }
        } primaryAction: { ids in
            if let row = row(ids) {
                actions.show(row)
            }
        }
    }

    func row(_ ids: Set<HistoryRow.ID>) -> HistoryRow? {
        rows.first { ids.contains($0.id) }
    }
}

struct BackupsPage: View {
    let rows: [BackupRow]
    let now: Date

    var body: some View {
        if rows.isEmpty {
            Note(title: "No backups yet", text: "The server makes one each hour.")
        } else {
            Table(rows) {
                TableColumn("Backup") { row in
                    Text(row.when(now: now))
                        .font(Theme.mono(11))
                        .foregroundStyle(row.id == "live" ? Theme.accent : Color.primary)
                }
                .width(min: 200, ideal: 300)
                TableColumn("Where") { Text($0.place).font(Theme.mono(11)).foregroundStyle(.secondary) }.width(min: 120, ideal: 220)
                TableColumn("Size") { Text($0.size).font(Theme.mono(11)).foregroundStyle(.secondary) }.width(min: 60, ideal: 90)
            }
            .alternatingRowBackgrounds(.disabled)
        }
    }
}

struct DomainsPage: View {
    let domains: [String]
    let actions: DashboardActions

    var body: some View {
        if domains.isEmpty {
            Note(title: "No domains", text: "This app is not on the internet.")
        } else {
            List(domains, id: \.self) { domain in
                HStack {
                    Text(domain).font(Theme.mono(12)).textSelection(.enabled)
                    Spacer()
                    Button("Copy") { actions.copy(domain) }.controlSize(.small)
                    if !domain.hasSuffix("localhost"), let link = URL(string: "https://" + domain) {
                        Button("Open") { actions.open(link) }.controlSize(.small)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct LogsPage: View {
    let lines: [String]
    @Binding var filter: String
    let follow: Bool

    var body: some View {
        Group {
            if lines.isEmpty {
                Asking(what: "the logs")
            } else {
                LogText(lines: filter.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(filter) }, mark: filter, follow: follow)
            }
        }
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter")
    }
}

/// Lines of a machine in a text view of macOS: a selection goes over many
/// lines, and a long log costs nothing to scroll.
struct LogText: NSViewRepresentable {
    let lines: [String]
    var mark = ""
    var follow = false

    final class Shown {
        var count = 0
        var first: String?
        var mark = ""
    }

    func makeCoordinator() -> Shown { Shown() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 10)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        let shown = context.coordinator
        // New lines go at the end. Anything else, like a new filter, starts again.
        if lines.count < shown.count || lines.first != shown.first || mark != shown.mark {
            storage.setAttributedString(NSAttributedString())
            shown.count = 0
        }
        if lines.count > shown.count {
            storage.append(attributed(lines[shown.count...]))
        }
        (shown.count, shown.first, shown.mark) = (lines.count, lines.first, mark)
        if follow {
            text.scrollToEndOfDocument(nil)
        }
    }

    func attributed(_ part: ArraySlice<String>) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString(string: part.map { $0 + "\n" }.joined(), attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        guard !mark.isEmpty else { return result }
        let string = result.string as NSString
        var from = 0
        while from < string.length {
            let found = string.range(of: mark, options: .caseInsensitive, range: NSRange(location: from, length: string.length - from))
            guard found.location != NSNotFound else { break }
            result.addAttributes([.foregroundColor: NSColor(Theme.accent), .underlineStyle: NSUnderlineStyle.single.rawValue], range: found)
            from = found.location + found.length
        }
        return result
    }
}

/// The output of one change of the history.
struct EntrySheet: View {
    let entry: Entry
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entry.title).font(Theme.mono(12, .semibold)).lineLimit(1)
                Spacer()
                Text("$ chasen " + entry.command).font(Theme.mono(11)).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            .padding(14)
            Divider()
            if let lines = entry.lines {
                LogText(lines: lines)
            } else {
                Asking(what: "the output")
            }
            Divider()
            HStack {
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 720, height: 460)
    }
}

// MARK: - While nothing shows

struct Asking: View {
    let what: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Asking \(what)").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Something to read in place of a page: an empty part, or a failure.
struct Note: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
