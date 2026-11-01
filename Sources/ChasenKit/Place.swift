import Foundation

/// What the window shows: a server with its map, or one app with its tabs.
public enum Place: Hashable, Sendable {
    case server(String)
    case app(server: String, app: String)

    public var server: String {
        switch self {
        case .server(let name), .app(let name, _): name
        }
    }

    public var app: String? {
        if case .app(_, let app) = self { app } else { nil }
    }
}

/// The parts of an app, in the order of the tabs of the screen.
public enum AppTab: String, CaseIterable, Sendable, Identifiable {
    case overview, history, backups, domains, logs

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// What the window knows about one app. Nil is a part that has not come yet.
public struct Facts: Equatable, Sendable {
    public var status: AppStatus?
    public var history: [HistoryRow]?
    public var backups: [BackupRow]?
    public var domains: [String]?
    public var logs: [String] = []
    /// The last answer failed, with what the CLI said.
    public var problem: String?

    public init(status: AppStatus? = nil, history: [HistoryRow]? = nil, backups: [BackupRow]? = nil, domains: [String]? = nil, logs: [String] = [], problem: String? = nil) {
        self.status = status
        self.history = history
        self.backups = backups
        self.domains = domains
        self.logs = logs
        self.problem = problem
    }
}

/// The output of one row of the history, for its sheet.
public struct Entry: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// The line of the CLI that prints the same.
    public var command: String
    /// Nil while it comes.
    public var lines: [String]?

    public init(id: String, title: String, command: String, lines: [String]? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.lines = lines
    }
}
