import Foundation

/// The state of the menu bar: how the whisk looks, and the one line at the
/// top of the panel.
public struct Mood: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        /// No server yet, or no answer yet.
        case empty
        /// Every app is up and no server has an alert.
        case calm
        /// A server has a warning, or does not answer.
        case warning
        /// An app is down, or a server has an error.
        case trouble
    }

    public var level: Level
    /// A change ships a version on a server: the whisk moves.
    public var busy: Bool
    public var line: String

    public init(level: Level, busy: Bool, line: String) {
        self.level = level
        self.busy = busy
        self.line = line
    }

    /// Before the first answer of the servers.
    public static let asking = Mood(level: .empty, busy: false, line: "Asking your servers")

    /// The CLI stopped, and starts again soon.
    public static let stopped = Mood(level: .warning, busy: false, line: "Chasen stopped")
}

extension Overview {
    public var mood: Mood {
        let apps = servers.flatMap(\.apps)
        // A deploy stops a private app for a few seconds: that is not down.
        let down = apps.filter { !$0.up && !$0.ships }
        let alerts = servers.flatMap(\.alerts)
        let errors = alerts.filter(\.error).count
        let silent = servers.filter { $0.error != nil }
        let warnings = alerts.count - errors + silent.count
        let shipping = apps.filter(\.ships)

        var level = Mood.Level.calm
        if servers.isEmpty { level = .empty }
        if warnings > 0 { level = .warning }
        if !down.isEmpty || errors > 0 { level = .trouble }
        let busy = !shipping.isEmpty

        // The line says the most important thing: trouble, then a change, then a warning.
        let line: String
        switch true {
        case servers.isEmpty:
            line = "Not logged in"
        case down.count == 1:
            line = "\(down[0].app) is down"
        case down.count > 1:
            line = "\(down.count) apps down"
        case errors > 0:
            line = counted(errors, "error", "errors")
        case busy:
            line = shipping.count == 1 ? "\(shipping[0].change ?? "change") \(shipping[0].app)" : "\(shipping.count) changes run"
        case warnings == 1 && silent.count == 1:
            line = "\(silent[0].name) does not answer"
        case warnings > 0:
            line = counted(warnings, "warning", "warnings")
        case apps.isEmpty:
            line = "No apps yet"
        default:
            line = "\(counted(apps.count, "app", "apps")) up"
        }
        return Mood(level: level, busy: busy, line: line)
    }
}

/// "1 app", "3 apps".
public func counted(_ n: Int, _ one: String, _ many: String) -> String {
    "\(n) \(n == 1 ? one : many)"
}
