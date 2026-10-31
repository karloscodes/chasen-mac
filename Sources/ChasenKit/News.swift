import Foundation

/// One notification: what changed on a server since the last answer.
public struct News: Equatable, Sendable {
    public var title: String
    public var body: String
    /// What a click on the notification opens: the app on the internet.
    public var link: URL?
    /// Something is wrong: the notification makes a sound.
    public var trouble: Bool

    public init(title: String, body: String, link: URL? = nil, trouble: Bool = false) {
        self.title = title
        self.body = body
        self.link = link
        self.trouble = trouble
    }
}

extension Overview {
    /// What a person wants to know since the overview of before: an app that
    /// went live, an app that went down or came back, a new error on a
    /// server. A server that did not answer, now or before, tells nothing: a
    /// computer that wakes from sleep would ring for each of its apps.
    public func news(since before: Overview) -> [News] {
        var news: [News] = []
        for server in servers where server.error == nil {
            guard let old = before.servers.first(where: { $0.name == server.name }), old.error == nil else { continue }
            var told: [String] = []
            for app in server.apps {
                var said: [News] = []
                if let was = old.apps.first(where: { $0.app == app.app }) {
                    said = app.news(since: was, on: server.name)
                } else if app.up && !app.ships {
                    // A first deploy that ended between two asks.
                    said = [app.live(on: server.name, subject: nil)]
                }
                if said.contains(where: \.trouble) {
                    told.append(app.app)
                }
                news += said
            }
            // An app that goes down has an alert too: "shop is down: its
            // container is exited". The news of the app said it already.
            let known = Set(old.alerts.map(\.what))
            for alert in server.alerts where alert.error && !known.contains(alert.what) {
                if told.contains(where: { alert.what.hasPrefix($0 + " ") }) {
                    continue
                }
                news.append(News(title: server.name, body: alert.what, trouble: true))
            }
        }
        return news
    }
}

extension Overview.App {
    func news(since was: Overview.App, on server: String) -> [News] {
        if ships {
            return []
        }
        // A version that changed between two asks, with no change seen, was a deploy.
        let ended = was.ships ? was.change ?? "deploy" : nil
        if ended != nil || version != was.version {
            let change = ended ?? "deploy"
            if !up {
                return [News(title: "\(app) is down", body: "after the \(change), on \(server)", trouble: true)]
            }
            if version != was.version {
                return [live(on: server, subject: was.subject)]
            }
            if change == "restart" {
                return []
            }
            // The same version: a deploy that failed its health check, a
            // deploy of the same tag, or an auto-update, which keeps its tag.
            return [News(title: "The \(change) of \(app) ended", body: "\(version) runs on \(server)", link: link)]
        }
        if was.up && !up {
            return [News(title: "\(app) is down", body: "on \(server)", trouble: true)]
        }
        if !was.up && up {
            return [News(title: "\(app) runs again", body: "\(version) on \(server)", link: link)]
        }
        return []
    }

    func live(on server: String, subject: String?) -> News {
        let place = "\(version) on \(server)"
        return News(title: "\(app) is live", body: subject.map { "\($0)\n\(place)" } ?? place, link: link)
    }
}
