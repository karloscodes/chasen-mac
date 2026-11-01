import Foundation
import Testing
@testable import ChasenKit

@Suite("The map of a server")
struct MapTests {
    let now = Date(timeIntervalSince1970: 1_790_856_000) // 2026-10-01 12:00:00 UTC
    let shop = Overview.App(app: "shop", state: "Up 3 hours", version: "3f9a2c1d5e8b", domains: ["shop.example.com"], databases: 2, backup: "20261001T110000Z", replica: "live")
    let blog = Overview.App(app: "blog", state: "Exited (1) 3 minutes ago", up: false, version: "1.2.0", domains: ["blog.example.com"], databases: 1, backup: "off", replica: "off")

    func text(_ line: MapLine) -> String {
        line.cells.map(\.text).joined()
    }

    func map(_ apps: [Overview.App], load: ServerLoad? = nil, width: Int = 120, frame: Int = 0) -> [MapLine] {
        Map.lines(of: Overview.Server(name: "example.com", apps: apps), load: load, width: width, frame: frame, now: now)
    }

    @Test("draws the traffic from the internet through the proxy to each app")
    func branches() {
        let lines = map([shop, blog])

        #expect(text(lines[0]).hasPrefix("internet •━━━▶ proxy ━┳•━━━▶ ● shop"))
        #expect(text(lines[0]).contains("3f9a2c1 "))
        #expect(lines[0].app == "shop")
        #expect(text(lines[2]).hasPrefix("                      ┗━━╳━▶ ✗ blog"))
        #expect(lines[2].app == "blog")
    }

    @Test("says where the data of an app goes")
    func data() {
        let lines = map([shop, blog], load: ServerLoad("Bucket:   my-backups\n"))

        #expect(text(lines[0]).contains("2 db  ───▶ backup 1 h ago"))
        #expect(text(lines[0]).hasSuffix("───▶ my-backups"))
        #expect(text(lines[1]).contains("•··▶ live replica"))
        #expect(text(lines[2]).contains("backups off"))
    }

    @Test("a backup more than two hours old is red")
    func lateBackup() {
        var late = shop
        late.backup = "20261001T080000Z"

        let age = map([late])[0].cells.first { $0.text.hasPrefix("backup ") }

        #expect(age?.tone == .bad)
    }

    @Test("a dot moves along a line that is open, and leaves a pause between two passes")
    func motion() {
        let second = map([shop], frame: 2)
        let pause = map([shop], frame: 4)

        #expect(text(second[0]).hasPrefix("internet ━━•━▶"))
        #expect(!text(pause[0]).hasPrefix("internet •"))
        #expect(!text(pause[0]).prefix(13).contains("•"))
    }

    @Test("an app that runs a change says so in place of its version")
    func running() {
        var deploying = shop
        deploying.running = "deploy Fix login"

        #expect(text(map([deploying], frame: 0)[0]).contains("⠋ shop"))
        #expect(text(map([deploying], frame: 0)[0]).contains("deploy Fix login"))
    }

    @Test("the jobs have a line of their own")
    func jobs() {
        var worker = shop
        worker.jobs = "Up 3 hours"

        let lines = map([worker])

        #expect(text(lines[2]).contains("└ jobs  ● Up 3 hours"))
        #expect(lines[2].app == "shop")
    }

    @Test("a narrow window has shorter lines")
    func compact() {
        let wide = map([shop], width: 120)
        let narrow = map([shop], width: 90)

        #expect(text(narrow[0]).count < text(wide[0]).count)
        #expect(text(narrow[0]).hasPrefix("internet •━▶ proxy ━━•━▶"))
    }

    @Test("ends with the way you reach a server with no address on the web")
    func ssh() {
        let lines = map([shop], load: ServerLoad("API:      SSH only: not on the web\n"))

        #expect(text(lines.last!) == "you ──── ssh ────▶ API   SSH only: not on the web")
    }

    @Test("gives the API a branch of its own when it is on the web")
    func apiOnTheWeb() {
        let lines = map([shop], load: ServerLoad("API:      https://api.example.com\n"))

        #expect(text(lines[0]).contains("proxy ━┳"))
        #expect(text(lines.last!).contains("◆ API"))
        #expect(text(lines.last!).hasSuffix("https://api.example.com"))
    }
}
