# Chasen for Mac

The menu bar app of Chasen. Public, Apache 2.0, like `karloscodes/chasen`. It is a client of the `chasen` CLI, not of the protocol: it runs `chasen overview --watch` and reads one line of JSON each time. The CLI is the source of those fields (`cmd/chasen/overview.go`), so a change there comes first, with a release, then `bin/cli <version>` here.

## Commands

```bash
swift test        # ChasenKit: the overview, the mood of the menu bar, the news
bin/build 0.1.0   # build/Chasen-0.1.0.dmg. macOS only
snapshot dashboard <dir>   # the window in each part, with sample servers, to PNG
open -g --env CHASEN_DASHBOARD=1 /Applications/Chasen.app   # the real window behind the others, with no click: for a test
```

ChasenKit is Foundation only, so its tests also run on Linux in the `swift` image. ChasenUI, the app, and `snapshot` need macOS. On hq, CI on GitHub's macOS runner builds them; `snapshot panels <dir>` renders the panel in each state to PNG, and CI keeps the files with the disk image.

## Decisions

- The app never opens Terminal. The panel shows the servers, opens the dashboard, copies addresses, and adds servers. A login runs `chasen add server` in the app, and ssh asks its questions through `bin/askpass`, in dialogs of macOS.
- The dashboard (`Dashboard.swift`, `Board.swift`) is the screen of the CLI as a window of macOS: the sidebar and the toolbar of the system, with the words, the amber, and the lines of the screen. It only reads: it runs `load`, `status`, `history`, `backups`, `domains`, and `logs`, the commands that the screen calls harmless. Restart, rollback, restore, and every other change of a server stay in the CLI.
- Those commands print text. `Report.swift` reads it by the rules of `cmd/chasen/tui.go`, and `Map.swift` draws the map of `cmd/chasen/tui_map.go`, so a change there comes here too. The window keeps the map in characters, not in a drawing: it is the look of the CLI, and the tests read it as text.
- Each of those commands is one process and, through SSH, one login, so the window asks only for what it shows, every 30 seconds, and only while it is open. `overview --watch` keeps its own connection.
- The CLI of `cli.txt` is inside the app (`Contents/Helpers/chasen`), with its sha256 pinned, and a person never sees it. The app runs it without a terminal, so it never updates itself and the bundle stays as it was signed.
- The logins are one file, `credentials.json` of the CLI. Every chasen of the Mac reads it at each ask, so a login in the app is a login in the CLI, and the other way. The app holds no token.
- An ask of the CLI has 30 seconds for each server, and it ends ssh after that. A key in 1Password waits for a person, so ssh says nothing and the CLI says `context deadline exceeded`. The panel turns that into what to do (`Overview.Server.advice`). The panel also shows what ssh says on stderr, which the overview does not have.
- Read a pipe with `readLines`, never `FileHandle.bytes`: every `AsyncBytes` of a process shares one serial queue, so a silent stderr stops stdout.
- A panel of macOS first: the material of the system, light and dark, SF for words, native fields and buttons, rounded rows under the pointer. What is Chasen's: the amber of the screen of the CLI for an app that runs, SF Mono for all that the machine says, and red only for a failure. The mark is the pixel whisk of `src/data/mark.ts` of chasenhq.com, in `Mark.swift`.
- The themes are the three of the CLI (`cmd/chasen/theme.go`): chasen, monochrome, and terminal, which the app calls System and takes from the accent color of macOS. The choice is the file `theme` next to `credentials.json`, so the app and the screen of the CLI share it, and the app reads it again when a window opens. A theme changes the panel and the dashboard. The menu bar keeps its own colors: red there is a signal, not a look. Monochrome has no color to say that something is wrong, so a view that says it with color needs a second way: `Dot`, a bold underline, a word.
- The menu bar: dim when calm, the full color of the bar for a warning, red for trouble. It sways for a change that ships a version (`Overview.App.shipping`), not for a cron job, a shell, or a download.
- Notifications only for what a person acts on. A server that does not answer rings nothing.
- Signed ad hoc. A Developer ID and notarization wait for an Apple Developer account of the user.
