import AppKit
import ChasenKit
import UserNotifications

/// The notifications of the news: an app that went live, went down, or came
/// back, and a new error on a server. A click opens the app.
@MainActor
final class Notices: NSObject, UNUserNotificationCenterDelegate {
    /// Outside the app (swift run) there is no bundle, and no notifications.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ news: News) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = news.title
        content.body = news.body
        if news.trouble {
            content.sound = .default
        }
        if let link = news.link {
            content.userInfo = ["link": link.absoluteString]
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        if let link = response.notification.request.content.userInfo["link"] as? String, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
        done()
    }

    /// A menu bar app is always in front: show the banner anyway.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
