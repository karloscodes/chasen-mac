import Testing
@testable import ChasenKit

@Suite("The mood of the menu bar")
struct MoodTests {
    let shop = Overview.App(app: "shop", version: "1.4.2", domains: ["shop.example.com"])
    let blog = Overview.App(app: "blog", version: "3f9a2c1", domains: ["blog.example.com"])

    @Test("with no server, it is not logged in")
    func noServer() {
        let mood = Overview(servers: []).mood

        #expect(mood == Mood(level: .empty, busy: false, line: "not logged in"))
    }

    @Test("with every app up, it is calm and counts them")
    func allUp() {
        let mood = Overview(servers: [.init(name: "example.com", apps: [shop, blog])]).mood

        #expect(mood == Mood(level: .calm, busy: false, line: "2 apps up"))
    }

    @Test("a warning, or a server that does not answer, is a warning")
    func warnings() {
        let warned = Overview(servers: [.init(name: "example.com", apps: [shop], alerts: [.init(error: false, what: "No offsite backups", fix: "")])])
        let silent = Overview(servers: [.init(name: "example.com", apps: [shop]), .init(name: "203.0.113.5", error: "timed out")])

        #expect(warned.mood == Mood(level: .warning, busy: false, line: "1 warning"))
        #expect(silent.mood == Mood(level: .warning, busy: false, line: "203.0.113.5 does not answer"))
    }

    @Test("an app that is down, or an error, is trouble, and the line says it before a deploy")
    func trouble() {
        var down = blog
        down.up = false
        var deploying = shop
        deploying.running = "deploy Fix login redirect"
        let error = Overview.Alert(error: true, what: "The disk is 93% full", fix: "")

        let mood = Overview(servers: [.init(name: "example.com", apps: [deploying, down])]).mood
        let alerted = Overview(servers: [.init(name: "example.com", apps: [shop], alerts: [error])]).mood

        #expect(mood == Mood(level: .trouble, busy: true, line: "blog is down"))
        #expect(alerted == Mood(level: .trouble, busy: false, line: "1 error"))
    }

    @Test("a deploy moves the whisk, and a cron job or a shell does not")
    func busy() {
        var deploying = shop
        deploying.running = "deploy Fix login redirect"
        var cron = blog
        cron.running = "cron bin/rails cleanup"
        var shell = blog
        shell.running = "ssh"

        #expect(Overview(servers: [.init(name: "example.com", apps: [deploying, blog])]).mood == Mood(level: .calm, busy: true, line: "deploy shop"))
        #expect(Overview(servers: [.init(name: "example.com", apps: [shop, cron])]).mood.busy == false)
        #expect(Overview(servers: [.init(name: "example.com", apps: [shop, shell])]).mood.busy == false)
    }

    @Test("an app that deploys is not down: a private app stops for a few seconds")
    func deployingIsNotDown() {
        let admin = Overview.App(app: "admin", up: false, version: "0.9.1", running: "deploy", listen: "127.0.0.1:8080")

        let mood = Overview(servers: [.init(name: "example.com", apps: [admin])]).mood

        #expect(mood == Mood(level: .calm, busy: true, line: "deploy admin"))
    }
}
