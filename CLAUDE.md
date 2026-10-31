# Chasen for Mac

The menu bar app of Chasen. Public, Apache 2.0, like `karloscodes/chasen`. It is a client of the `chasen` CLI, not of the protocol: it runs `chasen overview --watch` and reads one line of JSON each time. The CLI is the source of those fields (`cmd/chasen/overview.go`), so a change there comes first, with a release, then `bin/cli <version>` here.

## Commands

```bash
swift test        # ChasenKit: the overview, the mood of the menu bar, the news
bin/build 0.1.0   # build/Chasen-0.1.0.dmg. macOS only
```

ChasenKit is Foundation only, so its tests also run on Linux in the `swift` image. ChasenUI, the app, and `snapshot` need macOS. On hq, CI on GitHub's macOS runner builds them; `snapshot panels <dir>` renders the panel in each state to PNG, and CI keeps the files with the disk image.

## Decisions

- The panel shows, the screen acts. The panel opens apps and copies addresses. Logs, history, rollback, restore, and every other change of a server happen in `chasen` in Terminal (`open the screen`). Do not rebuild the screen in SwiftUI.
- The CLI of `cli.txt` is inside the app (`Contents/Helpers/chasen`), with its sha256 pinned. The app runs it without a terminal, so it never updates itself and the bundle stays as it was signed. Terminal runs the `chasen` of the shell when there is one, else this one.
- The brand of chasenhq.com: stone greys, one amber accent for "live", red only for a failure, mono type, square corners. The mark is the pixel whisk of `src/data/mark.ts` of chasenhq.com, in `Mark.swift`.
- The menu bar: dim when calm, the full color of the bar for a warning, red for trouble. It sways for a change that ships a version (`Overview.App.shipping`), not for a cron job, a shell, or a download.
- Notifications only for what a person acts on. A server that does not answer rings nothing.
- Signed ad hoc. A Developer ID and notarization wait for an Apple Developer account of the user.
