import Foundation
import Testing
@testable import ChasenKit

@Suite("A line of chasen overview --watch")
struct OverviewTests {
    @Test("reads the servers, their apps, and their alerts")
    func readsALine() throws {
        let line = """
        {"servers":[{"name":"example.com","apps":[{"app":"shop","state":"Up 2 hours (healthy)","up":true,"version":"1.4.2","running":"deploy Fix login redirect","since":"2026-10-31T09:00:00Z","id":42,"domains":["shop.example.com"],"databases":1},{"app":"admin","state":"Up 3 days","up":true,"version":"0.9.1","private":"127.0.0.1:8080"}],"alerts":[{"error":true,"what":"The disk is 93% full","fix":"Make space"}]}],"running":1,"down":0,"errors":1,"warnings":0}
        """

        let overview = try #require(Overview.line(line))

        let server = try #require(overview.servers.first)
        #expect(server.name == "example.com")
        #expect(server.apps.map(\.app) == ["shop", "admin"])
        #expect(server.apps[0].subject == "Fix login redirect")
        #expect(server.apps[0].link == URL(string: "https://shop.example.com"))
        #expect(server.apps[1].listen == "127.0.0.1:8080")
        #expect(server.apps[1].link == nil)
        #expect(server.apps[1].address == "127.0.0.1:8080")
        #expect(server.alerts == [Overview.Alert(error: true, what: "The disk is 93% full", fix: "Make space")])
    }

    @Test("takes the first domain on the internet: a .localhost domain answers only on the server")
    func skipsLocalhostDomains() {
        let app = Overview.App(app: "shop", version: "1.4.2", domains: ["shop.server.localhost", "shop.example.com"])
        let local = Overview.App(app: "admin", version: "0.9.1", domains: ["admin.server.localhost"])

        #expect(app.domain == "shop.example.com")
        #expect(app.link == URL(string: "https://shop.example.com"))
        #expect(local.domain == nil)
        #expect(local.link == nil)
    }

    @Test("reads a server from before the domains, and a server that does not answer")
    func readsOlderServers() throws {
        let line = #"{"servers":[{"name":"old.example.com","apps":[{"app":"blog","state":"Up","up":true,"version":"3f9a2c1"}],"alerts":[]},{"name":"203.0.113.5","error":"ssh: connect to host 203.0.113.5 port 22: Operation timed out","apps":[],"alerts":[]}]}"#

        let overview = try #require(Overview.line(line))

        #expect(overview.servers[0].apps[0].link == nil)
        #expect(overview.servers[1].error?.hasPrefix("ssh:") == true)
    }

    @Test("says what to do when ssh runs out of time")
    func sshOutOfTime() {
        let waiting = Overview.Server(name: "example.com", error: #"cannot reach the server through SSH (ssh://ubuntu@203.0.113.5): Post "http://chasen-server/v1/overview?arg=--json": context deadline exceeded. Does ssh log in to it, and does it have chasen-server 0.6 or newer?"#)
        let closed = Overview.Server(name: "example.com", error: #"cannot reach the server through SSH (ssh://ubuntu@203.0.113.5): Post "http://chasen-server/v1/overview?arg=--json": EOF. Does ssh log in to it, and does it have chasen-server 0.6 or newer?"#)
        let web = Overview.Server(name: "example.com", error: #"Post "https://api.example.com/v1/overview?arg=--json": context deadline exceeded"#)

        #expect(waiting.advice == "ssh did not log in within 30 seconds. If 1Password asks for your key, approve it.")
        #expect(closed.advice == nil)
        #expect(web.advice == nil)
    }

    @Test("is nil for a line that is not an overview")
    func refusesOtherLines() {
        #expect(Overview.line("Error: not logged in") == nil)
    }
}
