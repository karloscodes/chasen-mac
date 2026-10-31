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

    @Test("reads a server from before the domains, and a server that does not answer")
    func readsOlderServers() throws {
        let line = #"{"servers":[{"name":"old.example.com","apps":[{"app":"blog","state":"Up","up":true,"version":"3f9a2c1"}],"alerts":[]},{"name":"203.0.113.5","error":"ssh: connect to host 203.0.113.5 port 22: Operation timed out","apps":[],"alerts":[]}]}"#

        let overview = try #require(Overview.line(line))

        #expect(overview.servers[0].apps[0].link == nil)
        #expect(overview.servers[1].error?.hasPrefix("ssh:") == true)
    }

    @Test("is nil for a line that is not an overview")
    func refusesOtherLines() {
        #expect(Overview.line("Error: not logged in") == nil)
    }
}
