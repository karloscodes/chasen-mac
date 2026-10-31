import AppKit

/// Runs chasen in a new window of Terminal: the screen, or a login. It is
/// the chasen of your shell when you installed one, so it is the newest, or
/// the one inside the app.
enum Terminal {
    static func run(_ arguments: [String]) {
        let words = arguments.map(quote).joined(separator: " ")
        let script = """
        #!/bin/zsh -l
        # Chasen for Mac opened this window.
        cd ~
        if command -v chasen >/dev/null 2>&1; then
          chasen \(words)
        else
          CHASEN_NO_UPDATE_CHECK=1 \(quote(CLI.url.path)) \(words)
        fi

        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chasen.command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        } catch {
            return
        }
        NSWorkspace.shared.open(file)
    }

    /// A word for the shell, in single quotes.
    static func quote(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
