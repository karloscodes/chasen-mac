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
            Root(feed: delegate.feed)
        } label: {
            MenuIcon(feed: delegate.feed)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    let feed = Feed()
    let notices = Notices()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A write to a CLI that stopped must not stop the app.
        signal(SIGPIPE, SIG_IGN)
        notices.start()
        feed.onNews = { [notices] news in news.forEach(notices.post) }
        feed.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        feed.stop()
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
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Panel(overview: feed.overview, problem: feed.problem, sway: feed.sway, about: about, atLogin: $atLogin, actions: PanelActions(
            open: { NSWorkspace.shared.open($0) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            screen: { Terminal.run([]) },
            login: { Terminal.run(["add", "server", $0]) },
            retry: { feed.start() },
            quit: { NSApp.terminate(nil) }
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
