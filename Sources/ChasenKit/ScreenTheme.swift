import Foundation

/// The themes of the screen of the CLI (cmd/chasen/theme.go), and of the app:
///
///   - chasen: the amber of the Chasen mark. The default.
///   - monochrome: no color, only bold and dim.
///   - terminal: the colors of the system, so a switch of theme applies. The
///     CLI takes the 16 colors of the terminal, and the app the accent color
///     of macOS.
///
/// The choice is one file next to the logins, so t on the screen and the
/// choice in the app are one choice. CHASEN_THEME wins over it, in both.
public enum ScreenTheme: String, CaseIterable, Sendable, Identifiable {
    case chasen, monochrome, terminal

    public var id: String { rawValue }

    public var title: String {
        self == .terminal ? "System" : rawValue.capitalized
    }

    /// The next theme, in the order of t on the screen.
    public var next: ScreenTheme {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The file that the CLI writes: `theme`, next to `credentials.json`.
    public static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/chasen/theme")
    }

    public static func load(from file: URL = file, environment: [String: String] = ProcessInfo.processInfo.environment) -> ScreenTheme {
        let saved = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let name = environment["CHASEN_THEME"] ?? saved.trimmingCharacters(in: .whitespacesAndNewlines)
        // "ansi" and "omarchy" are the names of the terminal theme before.
        return ["ansi", "omarchy"].contains(name) ? .terminal : ScreenTheme(rawValue: name) ?? .chasen
    }

    public func save(to file: URL = file) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard FileManager.default.createFile(atPath: file.path, contents: Data((rawValue + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
