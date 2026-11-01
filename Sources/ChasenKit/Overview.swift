import Foundation

/// The overview of every server you are logged in to: one line of
/// `chasen overview --watch`. The CLI is the source of these fields, in
/// cmd/chasen/overview.go of karloscodes/chasen. A server from before a field
/// leaves it out, so every field that came later is optional.
public struct Overview: Codable, Equatable, Sendable {
    public var servers: [Server]

    public init(servers: [Server]) {
        self.servers = servers
    }

    public struct Server: Codable, Equatable, Sendable, Identifiable {
        /// The host of an SSH address, or the base domain of an address on the web.
        public var name: String
        /// Why the server did not answer, or nil.
        public var error: String?
        public var apps: [App]
        public var alerts: [Alert]

        public var id: String { name }

        public init(name: String, error: String? = nil, apps: [App] = [], alerts: [Alert] = []) {
            self.name = name
            self.error = error
            self.apps = apps
            self.alerts = alerts
        }

        /// What to do about an ask that ran out of time through SSH. ssh then
        /// says nothing: the CLI ends it while it waits for a signature, and a
        /// key in 1Password waits for a person. Nil for any other error.
        public var advice: String? {
            guard let error, error.contains("through SSH"), error.contains("context deadline exceeded") else { return nil }
            return "ssh did not log in within 30 seconds. If 1Password asks for your key, approve it."
        }
    }

    public struct App: Codable, Equatable, Sendable, Identifiable {
        public var app: String
        /// What Docker says of the container, like "Up 2 hours (healthy)".
        public var state: String
        public var up: Bool
        public var version: String
        /// The change that runs now, like "deploy Fix login redirect", or nil.
        public var running: String?
        /// When that change started, in RFC 3339.
        public var since: String?
        public var domains: [String]?
        /// Where a private app listens on the server, like 127.0.0.1:8080.
        public var listen: String?
        /// The state of the jobs container, when the app has one.
        public var jobs: String?
        /// The SQLite databases in the newest backup.
        public var databases: Int?
        /// The stamp of the newest backup, "" before the first, "off" with no backups.
        public var backup: String?
        /// The live replica: "live", "behind", or "off". A server from before it leaves it out.
        public var replica: String?

        public var id: String { app }

        enum CodingKeys: String, CodingKey {
            case app, state, up, version, running, since, domains, jobs, databases, backup, replica
            case listen = "private"
        }

        public init(app: String, state: String = "Up 2 hours", up: Bool = true, version: String, running: String? = nil, since: String? = nil, domains: [String]? = nil, listen: String? = nil, jobs: String? = nil, databases: Int? = nil, backup: String? = nil, replica: String? = nil) {
            self.app = app
            self.state = state
            self.up = up
            self.version = version
            self.running = running
            self.since = since
            self.domains = domains
            self.listen = listen
            self.jobs = jobs
            self.databases = databases
            self.backup = backup
            self.replica = replica
        }
    }

    public struct Alert: Codable, Equatable, Sendable, Identifiable {
        public var error: Bool
        public var what: String
        public var fix: String

        public var id: String { what }

        public init(error: Bool, what: String, fix: String) {
            self.error = error
            self.what = what
            self.fix = fix
        }
    }

    /// Reads one line of `chasen overview --watch`, or nil for a line that is
    /// not an overview.
    public static func line(_ text: String) -> Overview? {
        try? JSONDecoder().decode(Overview.self, from: Data(text.utf8))
    }
}

extension Overview.App {
    /// The changes that put a version on the server, or take one away. The
    /// menu bar moves while one runs. A cron job, a shell, or a download does
    /// not: they run often, and they change no version.
    public static let shipping: Set<String> = ["deploy", "enable", "rollback", "restore", "restart", "remove", "auto-update"]

    /// The first word of the change that runs: "deploy", "rollback", "cron".
    public var change: String? {
        running.flatMap { $0.split(separator: " ").first.map(String.init) }
    }

    /// A change that ships a version runs now.
    public var ships: Bool {
        change.map(Self.shipping.contains) ?? false
    }

    /// The subject of the commit of a deploy that runs: "Fix login redirect".
    public var subject: String? {
        guard change == "deploy", let running, let space = running.firstIndex(of: " ") else { return nil }
        return String(running[running.index(after: space)...])
    }

    /// The domain of the app on the internet, or nil for a private app. The
    /// proxy also serves a .localhost name, which answers only on the server.
    public var domain: String? {
        domains?.first { $0 != "localhost" && !$0.hasSuffix(".localhost") }
    }

    /// The address of the app on the internet, or nil for a private app.
    public var link: URL? {
        domain.flatMap { URL(string: "https://" + $0) }
    }

    /// Where the app answers: its domain, or its address on the server.
    public var address: String? {
        domain ?? listen
    }
}
