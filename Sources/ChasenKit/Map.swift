import Foundation

/// A piece of a line with one color.
public struct Cell: Equatable, Sendable {
    public enum Tone: Sendable {
        case plain, dim, bold, accent, bad
    }

    public var text: String
    public var tone: Tone

    public init(_ text: String, _ tone: Tone = .plain) {
        self.text = text
        self.tone = tone
    }
}

/// One line of the map. `app` is the app that a click on the line chooses.
public struct MapLine: Equatable, Sendable, Identifiable {
    public var id: Int
    public var cells: [Cell]
    public var app: String?
}

/// The map shows a server as what it is, the same as the screen of the CLI
/// (cmd/chasen/tui_map.go): the traffic that comes from the internet through
/// the proxy to each app, the jobs beside an app, and where its data goes.
///
/// A line moves when its path is open: an app that answers behind the proxy,
/// a live replica, a backup that runs. It does not count requests: the server
/// does not know them. A broken line is red, and it does not move.
public enum Map {
    static let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    /// The room of the columns for a width in characters. Under 100 the map
    /// has shorter lines and words.
    struct Layout {
        var compact = false
        var segment = 4 // the length of a line of traffic
        var name = 6 // the names of the apps
        var what = 16 // the version of an app, or what runs on it now

        /// The column of the trunk of the proxy.
        var trunk: Int { "internet ▶ proxy ━".count + segment }

        init(width: Int, apps: [Overview.App]) {
            if width < 100 {
                compact = true
                segment = 2
                what = 14
            }
            name = min(18, apps.map(\.app.count).max().map { max(name, $0) } ?? name)
        }
    }

    public static func lines(of server: Overview.Server, load: ServerLoad?, width: Int, frame: Int, now: Date) -> [MapLine] {
        let layout = Layout(width: width, apps: server.apps)
        let api = load?.api ?? ""
        let apiOnWeb = api.hasPrefix("https://")
        let branches = server.apps.count + (apiOnWeb ? 1 : 0)
        var lines: [MapLine] = []
        func add(_ cells: [Cell], app: String? = nil) {
            lines.append(MapLine(id: lines.count, cells: cells, app: app))
        }
        for (i, app) in server.apps.enumerated() {
            let phase = i * 3
            let last = i == branches - 1
            let live = app.up && !(app.domains ?? []).isEmpty
            let bucket = load?.bucket
            add(branch(i, last: last, branches: branches, layout, frame + phase, live: live, broken: !app.up)
                + appCells(app, layout, frame) + [Cell("  ")]
                + dataCells(app, bucket: bucket, frame + phase, layout, now), app: app.app)
            let under = [Cell(String(repeating: " ", count: layout.trunk)), Cell(last ? " " : "┃", .dim), Cell(String(repeating: " ", count: layout.segment + 1))]
            let place = app.listen.map { "private " + $0 } ?? (app.domains ?? []).joined(separator: " ")
            add(under + [Cell("   "), Cell(fit(place.isEmpty ? "no domain" : place, layout.name + 2 + layout.what), .dim), Cell("  ")]
                + replicaCells(app, bucket: bucket, frame + phase, layout), app: app.app)
            if let jobs = app.jobs {
                add(under + [Cell("   └ ", .dim), Cell("jobs  "), Cell("● ", jobs.hasPrefix("Up") ? .accent : .bad), Cell(jobs, .dim)], app: app.app)
            }
        }
        if apiOnWeb {
            add(branch(server.apps.count, last: true, branches: branches, layout, frame + server.apps.count * 3, live: true, broken: false)
                + [Cell(" ◆ ", .accent), Cell(fit("API", layout.name + 2), .bold), Cell(api, .accent)])
        } else if !api.isEmpty {
            let wire = String(repeating: "─", count: layout.segment)
            add([Cell("you ", .dim), Cell(wire + " ssh " + wire + "▶", .dim), Cell(" API   " + api, .dim)])
        }
        return lines
    }

    /// The traffic to one app: from the internet through the proxy for the
    /// first, and from the trunk of the proxy for the others.
    static func branch(_ i: Int, last: Bool, branches: Int, _ layout: Layout, _ frame: Int, live: Bool, broken: Bool) -> [Cell] {
        var cells: [Cell] = []
        if i == 0 {
            cells.append(Cell("internet ", .dim))
            cells += flow(layout.segment, frame, "━", live: live || broken, broken: false)
            cells += [Cell("▶", arrow(live: live || broken, broken: false)), Cell(" proxy ", .bold), Cell(branches > 1 ? "━┳" : "━━", .dim)]
        } else {
            cells += [Cell(String(repeating: " ", count: layout.trunk)), Cell(last ? "┗" : "┣", .dim)]
        }
        return cells + flow(layout.segment, frame, "━", live: live, broken: broken) + [Cell("▶", arrow(live: live, broken: broken))]
    }

    static func arrow(live: Bool, broken: Bool) -> Cell.Tone {
        broken ? .bad : live ? .accent : .dim
    }

    /// A line of a length. A live line has a dot that moves along it, one step
    /// a frame, with two frames of no dot between two passes, so the eye sees
    /// it start again. A broken line is red, with a cross in its middle.
    static func flow(_ length: Int, _ frame: Int, _ base: String, live: Bool, broken: Bool) -> [Cell] {
        if broken {
            let half = length / 2
            return [Cell(String(repeating: base, count: half) + "╳" + String(repeating: base, count: max(0, length - half - 1)), .bad)]
        }
        let at = frame % (length + 2)
        guard live, at < length else {
            return [Cell(String(repeating: base, count: length), .dim)]
        }
        return [Cell(String(repeating: base, count: at), .dim), Cell("•", .accent), Cell(String(repeating: base, count: length - at - 1), .dim)]
    }

    /// An app at the end of its branch: its state, its name, and its version
    /// or what runs on it now.
    static func appCells(_ app: Overview.App, _ layout: Layout, _ frame: Int) -> [Cell] {
        var dot = Cell("● ", .accent)
        var about = Cell(fit(short(app.version), layout.what), .dim)
        if let running = app.running {
            dot = Cell(spinner[frame % spinner.count] + " ", .accent)
            about = Cell(fit(running, layout.what), .accent)
        } else if !app.up {
            dot = Cell("✗ ", .bad)
            about = Cell(fit(app.state, layout.what), .bad)
        }
        return [Cell(" "), dot, Cell(fit(app.app, layout.name), .bold), Cell("  "), about]
    }

    /// A commit in 7 characters, like git shows it.
    public static func short(_ version: String) -> String {
        version.count > 7 && version.allSatisfy(\.isHexDigit) ? String(version.prefix(7)) : version
    }

    /// Where the data of an app goes each hour: its databases, the backup on
    /// the server, and its copy in the bucket. The line moves while a backup
    /// runs.
    static func dataCells(_ app: Overview.App, bucket: String?, _ frame: Int, _ layout: Layout, _ now: Date) -> [Cell] {
        guard app.replica != nil, let backup = app.backup else {
            return [Cell(app.replica == nil ? "the data shows after the next update of the server" : "no backup yet", .dim)]
        }
        if backup == "off" {
            return [Cell("backups off", .dim)]
        }
        if backup.isEmpty {
            return [Cell("no backup yet", .dim)]
        }
        let running = app.running?.hasPrefix("backup") ?? false
        let at = Report.stamp(backup)
        let when = at.map { Report.ago($0, now: now) } ?? backup
        let length = layout.compact ? 2 : 3
        let late = at.map { now.timeIntervalSince($0) > 7200 } ?? false
        let age = Cell(layout.compact ? fit(when, 11) : fit("backup " + when, 18), late ? .bad : .plain)
        var cells = [Cell(fit("\(app.databases ?? 0) db", 5) + " ", .dim)]
        cells += flow(length, frame, "─", live: running, broken: false)
        cells += [Cell("▶ ", arrow(live: running, broken: false)), age, Cell(" ")]
        guard let bucket else {
            return cells + [Cell("this server only", .dim)]
        }
        cells += flow(length, frame + 1, "─", live: running, broken: false)
        return cells + [Cell("▶ ", arrow(live: running, broken: false)), Cell(bucket)]
    }

    /// The live replica: each change of the databases on its way to the
    /// bucket, about a second behind.
    static func replicaCells(_ app: Overview.App, bucket: String?, _ frame: Int, _ layout: Layout) -> [Cell] {
        let pad = Cell(String(repeating: " ", count: 6))
        let length = layout.compact ? 2 : 3
        switch app.replica {
        case "live":
            return [pad] + flow(length, frame, "·", live: true, broken: false)
                + [Cell("▶ ", .accent), Cell(layout.compact ? fit("replica", 11) : fit("live replica", 18)), Cell(" ")]
                + flow(length, frame + 1, "·", live: true, broken: false)
                + [Cell("▶ ", .accent), Cell(bucket ?? "the bucket")]
        case "behind":
            return [pad] + flow(length, frame, "·", live: false, broken: true)
                + [Cell("▶ ", .bad), Cell("live replica behind: chasen verify", .bad)]
        default:
            return []
        }
    }

    /// Text cut to a width, with the rest filled with spaces.
    public static func fit(_ text: String, _ width: Int) -> String {
        if text.count > width {
            return text.prefix(width - 1) + "…"
        }
        return text + String(repeating: " ", count: width - text.count)
    }
}
