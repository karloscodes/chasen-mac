import ChasenKit
import ChasenUI
import ServiceManagement
import SwiftUI

/// Chasen for Mac: the whisk in the menu bar. It is dim while every app is
/// up, it sways while a deploy runs, and it is red when an app is down.
@main
struct ChasenApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            Root(feed: delegate.feed, signin: delegate.signin, dashboard: delegate.dashboard)
        } label: {
            MenuIcon(feed: delegate.feed)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    let feed = Feed()
    let signin = Signin()
    let notices = Notices()
    lazy var dashboard = DashboardWindow(board: Board(feed: feed), feed: feed)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A write to a CLI that stopped must not stop the app.
        signal(SIGPIPE, SIG_IGN)
        // t on the screen of the CLI changes the theme: read it when a window opens.
        Look.shared.theme = ScreenTheme.load()
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Look.shared.theme = ScreenTheme.load() }
        }
        notices.start()
        feed.onNews = { [notices] news in news.forEach(notices.post) }
        signin.onLogin = { [feed] in feed.reload() }
        feed.start()
        if ProcessInfo.processInfo.environment["CHASEN_DASHBOARD"] != nil {
            dashboard.showBehind()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        signin.cancel()
        feed.stop()
        dashboard.board.stop()
    }

    /// The app lives in the menu bar: the last window does not end it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuIcon: View {
    let feed: Feed

    var body: some View {
        Image(nsImage: Mark.menuImage(feed.mood.level, sway: feed.sway))
    }
}

struct Root: View {
    let feed: Feed
    let signin: Signin
    let dashboard: DashboardWindow
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Panel(overview: feed.overview, problem: feed.problem, sway: feed.sway, login: signin.state, said: feed.said, about: about, atLogin: $atLogin, actions: PanelActions(
            open: { NSWorkspace.shared.open($0) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            addServer: { signin.open() },
            login: { signin.start($0) },
            cancelLogin: { signin.cancel() },
            retry: { feed.start() },
            quit: { NSApp.terminate(nil) },
            dashboard: { dashboard.show($0) }
        ))
        // The panel opens: ask the servers now.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in feed.askNow() }
        .onChange(of: atLogin) { _, on in
            do {
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                atLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// "0.1.0 · chasen 0.13.0", from the Info.plist that bin/build writes.
    var about: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let app = info["CFBundleShortVersionString"] as? String ?? "dev"
        let cli = info["ChasenCLIVersion"] as? String ?? "dev"
        return "\(app) · chasen \(cli)"
    }
}
