import Foundation
import Testing
@testable import ChasenKit

@Suite("The news between two overviews")
struct NewsTests {
    let shop = Overview.App(app: "shop", version: "1.4.1", domains: ["shop.example.com"])

    func on(_ apps: Overview.App..., alerts: [Overview.Alert] = [], error: String? = nil) -> Overview {
        Overview(servers: [.init(name: "example.com", error: error, apps: apps, alerts: alerts)])
    }

    func shop(version: String = "1.4.1", up: Bool = true, running: String? = nil) -> Overview.App {
        var app = shop
        app.version = version
        app.up = up
        app.running = running
        return app
    }

    @Suite("when a deploy ends") struct DeployEnds {
        let t = NewsTests()

        @Test("with a new version, the app is live, with the subject of its commit and its link")
        func live() {
            let before = t.on(t.shop(running: "deploy Fix login redirect"))

            let news = t.on(t.shop(version: "1.4.2")).news(since: before)

            #expect(news == [News(title: "shop is live", body: "Fix login redirect\n1.4.2 on example.com", link: URL(string: "https://shop.example.com"))])
        }

        @Test("with the same version, it says that the deploy ended and which version runs")
        func sameVersion() {
            let before = t.on(t.shop(running: "deploy Fix login redirect"))

            let news = t.on(t.shop()).news(since: before)

            #expect(news == [News(title: "The deploy of shop ended", body: "1.4.1 runs on example.com", link: URL(string: "https://shop.example.com"))])
        }

        @Test("with the app down, it is trouble")
        func down() {
            let before = t.on(t.shop(running: "rollback 1.4.0"))

            let news = t.on(t.shop(version: "1.4.0", up: false)).news(since: before)

            #expect(news == [News(title: "shop is down", body: "after the rollback, on example.com", trouble: true)])
        }

        @Test("a restart that ends up says nothing: you asked for it")
        func restart() {
            let before = t.on(t.shop(running: "restart"))

            #expect(t.on(t.shop()).news(since: before) == [])
        }
    }

    @Test("a new version between two asks is live: a short deploy ends between them")
    func versionBetweenAsks() {
        let news = on(shop(version: "1.4.2")).news(since: on(shop()))

        #expect(news.map(\.title) == ["shop is live"])
        #expect(news.first?.body == "1.4.2 on example.com")
    }

    @Test("a change that still runs says nothing yet")
    func stillRunning() {
        let before = on(shop(running: "deploy"))

        #expect(on(shop(version: "1.4.2", up: false, running: "deploy")).news(since: before) == [])
    }

    @Test("an app that stops is down, and an app that starts again runs again")
    func downAndBack() {
        let down = on(shop(up: false)).news(since: on(shop()))
        let back = on(shop()).news(since: on(shop(up: false)))

        #expect(down == [News(title: "shop is down", body: "on example.com", trouble: true)])
        #expect(back == [News(title: "shop runs again", body: "1.4.1 on example.com", link: URL(string: "https://shop.example.com"))])
    }

    @Test("a cron job does not hide an app that goes down")
    func cronAndDown() {
        let news = on(shop(up: false, running: "cron bin/rails cleanup")).news(since: on(shop()))

        #expect(news.map(\.title) == ["shop is down"])
    }

    @Test("a new error rings once, and a warning does not ring")
    func alerts() {
        let disk = Overview.Alert(error: true, what: "The disk is 93% full", fix: "")
        let backups = Overview.Alert(error: false, what: "No offsite backups", fix: "")

        let first = on(shop(), alerts: [disk, backups]).news(since: on(shop()))
        let again = on(shop(), alerts: [disk, backups]).news(since: on(shop(), alerts: [disk]))

        #expect(first == [News(title: "example.com", body: "The disk is 93% full", trouble: true)])
        #expect(again == [])
    }

    @Test("an app that goes down rings once, not again for its alert")
    func downOnce() {
        let alert = Overview.Alert(error: true, what: "shop is down: its container is exited", fix: "")

        let news = on(shop(up: false), alerts: [alert]).news(since: on(shop()))

        #expect(news.map(\.title) == ["shop is down"])
    }

    @Test("a new app that is up is live: its first deploy ended between two asks")
    func firstDeploy() {
        let blog = Overview.App(app: "blog", version: "3f9a2c1", domains: ["blog.example.com"])

        let news = on(shop(), blog).news(since: on(shop()))

        #expect(news.map(\.title) == ["blog is live"])
    }

    @Test("a server that does not answer, now or before, says nothing: the computer woke from sleep")
    func silentServer() {
        let silent = on(error: "timed out")

        #expect(on(shop(up: false)).news(since: silent) == [])
        #expect(silent.news(since: on(shop())) == [])
    }

    @Test("a server you just logged in to says nothing about its apps")
    func newServer() {
        #expect(on(shop()).news(since: Overview(servers: [])) == [])
    }
}
