import Foundation
import Testing
@testable import ChasenKit

@Suite("The theme, one choice for the app and the CLI")
struct ThemeTests {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("theme")

    func saved(_ text: String) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test("with no choice, it is the amber of Chasen")
    func noChoice() {
        #expect(ScreenTheme.load(from: file, environment: [:]) == .chasen)
    }

    @Test("reads what t on the screen of the CLI saved, with its old names")
    func readsTheCLI() throws {
        try saved("monochrome\n")
        #expect(ScreenTheme.load(from: file, environment: [:]) == .monochrome)

        try saved("omarchy\n")
        #expect(ScreenTheme.load(from: file, environment: [:]) == .terminal)

        try saved("ansi\n")
        #expect(ScreenTheme.load(from: file, environment: [:]) == .terminal)
    }

    @Test("a name that it does not know is the default")
    func unknown() throws {
        try saved("neon\n")

        #expect(ScreenTheme.load(from: file, environment: [:]) == .chasen)
    }

    @Test("CHASEN_THEME wins over the choice")
    func environment() throws {
        try saved("monochrome\n")

        #expect(ScreenTheme.load(from: file, environment: ["CHASEN_THEME": "terminal"]) == .terminal)
    }

    @Test("a choice in the app is the line that the CLI reads, for the user only")
    func saves() throws {
        try ScreenTheme.terminal.save(to: file)

        #expect(try String(contentsOf: file, encoding: .utf8) == "terminal\n")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(ScreenTheme.load(from: file, environment: [:]) == .terminal)
    }

    @Test("a second choice replaces the first")
    func savesAgain() throws {
        try ScreenTheme.terminal.save(to: file)

        try ScreenTheme.chasen.save(to: file)

        #expect(ScreenTheme.load(from: file, environment: [:]) == .chasen)
    }

    @Test("goes to the next theme in the order of the CLI, and starts again")
    func next() {
        #expect(ScreenTheme.chasen.next == .monochrome)
        #expect(ScreenTheme.monochrome.next == .terminal)
        #expect(ScreenTheme.terminal.next == .chasen)
    }

    @Test("the theme of the terminal is the theme of the system on a Mac")
    func titles() {
        #expect(ScreenTheme.allCases.map(\.title) == ["Chasen", "Monochrome", "System"])
    }
}
