import Foundation

/// What the commands of the CLI print. Only `overview` has JSON: the screen of
/// the CLI reads the text of the others, and these are the same readings
/// (cmd/chasen/tui.go). A line that they do not know stays out of the way.
public enum Report {
    /// One line of a server, safe to show: no escape sequences, no control
    /// characters, and only the text after the last carriage return.
    public static func clean(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .newlines)
        if let end = text.unicodeScalars.lastIndex(of: "\r") {
            text = String(text.unicodeScalars[text.unicodeScalars.index(after: end)...])
        }
        text = text.replacing(#/\x1b\[[0-9;?]*[ -\/]*[@-~]|\x1b\][^\x07]*\x07|\x1b./#, with: "")
        var kept = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09: kept.append(" ")
            case 0..<0x20, 0x7f, 0x80...0x9f: break
            default: kept.append(scalar)
            }
        }
        return String(kept)
    }

    public static func lines(_ output: String) -> [String] {
        guard !output.isEmpty else { return [] }
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false).map { clean(String($0)) }
        while lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    /// The values of the lines "Name:  value".
    static func values(_ lines: [String], _ name: String) -> [String] {
        lines.compactMap { line in
            line.hasPrefix(name + ":") ? String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) : nil
        }
    }

    /// The addresses of `chasen servers`. The CLI sorts them, the same as the
    /// servers of the overview, so one index is one server.
    public static func addresses(_ output: String) -> [String] {
        lines(output).compactMap { $0.split(separator: " ").last.map(String.init) }
    }

    /// The cells of a row of a table: two or more spaces end a cell.
    static func cells(_ row: String, _ count: Int) -> [String] {
        row.trimmingCharacters(in: .whitespaces)
            .split(separator: #/\s{2,}/#, maxSplits: count - 1)
            .map(String.init)
    }

    /// How long ago a moment was, in the words of a person.
    public static func ago(_ then: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(then))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<172_800: return "\(seconds / 3600) h ago"
        default: return "\(seconds / 86400) days ago"
        }
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    /// The moment of a backup, from its name: 20261001T110000Z.
    static func stamp(_ text: String) -> Date? {
        formatter("yyyyMMdd'T'HHmmss'Z'").date(from: text)
    }

    static func moment(_ text: String) -> Date? {
        formatter("yyyy-MM-dd HH:mm:ss").date(from: text)
    }

    /// The name of a backup as a time: "Oct 1 12:00 UTC · 3 h ago".
    static func stampText(_ text: String, now: Date) -> String {
        guard let at = stamp(text) else { return text }
        return formatter("MMM d HH:mm").string(from: at) + " UTC · " + ago(at, now: now)
    }
}

/// `chasen load`: how busy the machine is, and where its API answers.
public struct ServerLoad: Equatable, Sendable {
    public struct Gauge: Equatable, Sendable, Identifiable {
        public var label: String
        /// How full, from 0 to 100. A load equal to the cores is full.
        public var used: Int
        public var value: String
        public var bad: Bool

        public var id: String { label }

        public init(label: String, used: Int, value: String, bad: Bool) {
            self.label = label
            self.used = used
            self.value = value
            self.bad = bad
        }
    }

    public var hardware = ""
    public var gauges: [Gauge] = []
    /// Where the backups go, or nil when they stay on the server.
    public var bucket: String?
    public var api: String?

    public init(_ output: String) {
        let lines = Report.lines(output)
        let load = Report.values(lines, "Load").first ?? ""
        let memory = Report.values(lines, "Memory").first ?? ""
        let disk = Report.values(lines, "Disk").first ?? ""
        var machine: [String] = []
        if let parts = load.firstMatch(of: #/\((\d+) cores, (\w+)\)/#) {
            machine += [String(parts.2), parts.1 + " cores"]
        }
        if let parts = memory.firstMatch(of: #/ of ([0-9.]+ GB)/#) {
            machine.append(String(parts.1))
        }
        hardware = machine.joined(separator: " · ")
        if let parts = load.firstMatch(of: #/^([0-9.]+) .*\((\d+) cores[,)]/#), let value = Double(parts.1), let cores = Int(parts.2), cores > 0 {
            gauges.append(Gauge(label: "load", used: Int(value * 100 / Double(cores)), value: String(parts.1), bad: value > Double(cores)))
        }
        for (label, text) in [("mem", memory), ("disk", disk)] {
            if let parts = text.firstMatch(of: #/\((\d+)%\)/#), let used = Int(parts.1) {
                gauges.append(Gauge(label: label, used: used, value: "\(used)%", bad: used >= 90))
            }
        }
        bucket = Report.values(lines, "Bucket").first.flatMap { $0.hasPrefix("none") ? nil : $0 }
        api = Report.values(lines, "API").first
    }
}

/// `chasen status` of one app.
public struct AppStatus: Equatable, Sendable {
    public struct Field: Equatable, Sendable, Identifiable {
        public var name: String
        public var value: String

        public var id: String { name + value }
    }

    public var state: String
    public var urls: [String]
    let lines: [String]

    public init(_ output: String) {
        // The proxy also serves a .localhost name, which answers only on the server.
        lines = Report.lines(output).filter { !($0.hasPrefix("URL:") && $0.hasSuffix(".localhost")) }
        state = Report.values(lines, "State").first ?? ""
        urls = Report.values(lines, "URL")
    }

    /// The fields of the overview of the screen, in its order.
    public func fields(now: Date) -> [Field] {
        func field(_ name: String, _ change: (String) -> String = { $0 }) -> [Field] {
            Report.values(lines, name).map { Field(name: name, value: change($0)) }
        }
        return field("Version") + field("URL") + field("Private")
            + field("Backup") { $0 == "none" ? "none yet" : Report.stampText($0, now: now) }
            + field("Replica") { $0 == "off" ? "off: the backups stay on the server" : $0 }
            + field("Disk")
    }
}

/// One row of `chasen history`: ID, WHEN (UTC), ACTION, RESULT, and TOOK from
/// a server that says it.
public struct HistoryRow: Equatable, Sendable, Identifiable {
    public enum Outcome: Sendable {
        case worked, failed, running
    }

    public var id: String
    var at: String
    public var action: String
    public var result: String
    public var took: String

    /// The rows of the output, with no header.
    public static func rows(_ output: String) -> [HistoryRow] {
        Report.lines(output).dropFirst().compactMap { line in
            let parts = Report.cells(line, 5)
            guard parts.count >= 4 else { return nil }
            return HistoryRow(id: parts[0], at: parts[1], action: parts[2], result: parts[3], took: parts.count == 5 ? parts[4] : "")
        }
    }

    public var outcome: Outcome {
        switch result {
        case "failed": .failed
        case "running": .running
        default: .worked
        }
    }

    public func when(now: Date) -> String {
        guard let moment = Report.moment(at) else { return at }
        return Report.formatterDay.string(from: moment) + " · " + Report.ago(moment, now: now)
    }
}

extension Report {
    static let formatterDay = formatter("MMM d HH:mm")
}

/// One row of `chasen backups`: its name, where it is, and its size from a
/// server that says it. "live" is the live replica.
public struct BackupRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var place: String
    public var size: String

    public static func rows(_ output: String) -> [BackupRow] {
        Report.lines(output).compactMap { line in
            let parts = Report.cells(line, 3)
            guard parts.count >= 2 else { return nil }
            return BackupRow(id: parts[0], place: parts[1], size: parts.count == 3 ? parts[2] : "")
        }
    }

    public func when(now: Date) -> String {
        id == "live" ? "live replica" : Report.stampText(id, now: now)
    }
}
