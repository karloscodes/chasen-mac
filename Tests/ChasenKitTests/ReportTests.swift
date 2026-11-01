import Foundation
import Testing
@testable import ChasenKit

@Suite("What the commands of the CLI print")
struct ReportTests {
    let now = Date(timeIntervalSince1970: 1_790_856_000) // 2026-10-01 12:00:00 UTC

    @Test("a line of a server loses what would move a terminal")
    func cleansALine() {
        #expect(Report.clean("\u{1b}[2J\u{1b}[31mThe app did not answer /up\u{1b}[0m") == "The app did not answer /up")
        #expect(Report.clean("10%\r50%\r100%\r\n") == "100%")
        #expect(Report.clean("a\tb\u{7}") == "a b")
    }

    @Test("the load gives the machine and its gauges")
    func readsTheLoad() {
        let load = ServerLoad("""
        Version:  0.13.0
        Load:     0.08 0.05 0.01 (2 cores, arm64)
        Memory:   0.9 GB of 3.8 GB (24%)
        Disk:     6 GB of 38 GB (16%)
        Bucket:   none: the backups stay on this server
        API:      SSH only: not on the web
        """)

        #expect(load.hardware == "arm64 · 2 cores · 3.8 GB")
        #expect(load.bucket == nil)
        #expect(load.api == "SSH only: not on the web")
        #expect(load.gauges == [
            .init(label: "load", used: 4, value: "0.08", bad: false),
            .init(label: "mem", used: 24, value: "24%", bad: false),
            .init(label: "disk", used: 16, value: "16%", bad: false),
        ])
    }

    @Test("a gauge is bad above the cores, or from 90% full")
    func badGauges() {
        let load = ServerLoad("""
        Load:     6.50 3.00 1.00 (4 cores, amd64)
        Memory:   3 GB of 4 GB (75%)
        Disk:     35 GB of 38 GB (92%)
        Bucket:   my-backups
        """)

        #expect(load.bucket == "my-backups")
        #expect(load.gauges.map(\.bad) == [true, false, true])
    }

    @Test("the status gives the fields of an app, in the words of the screen")
    func readsTheStatus() {
        let status = AppStatus("""
        App:      shop
        Version:  3f9a2c1d5e8b
        State:    Up 3 hours (healthy)
        URL:      https://shop.example.com
        URL:      https://shop.com
        Disk:     data 12 MB · backups 40 MB in 3 · image 180 MB
        Backup:   20261001T110000Z
        Replica:  off
        """)

        #expect(status.state == "Up 3 hours (healthy)")
        #expect(status.urls == ["https://shop.example.com", "https://shop.com"])
        #expect(status.fields(now: now).map(\.value) == [
            "3f9a2c1d5e8b",
            "https://shop.example.com",
            "https://shop.com",
            "Oct 1 11:00 UTC · 1 h ago",
            "off: the backups stay on the server",
            "data 12 MB · backups 40 MB in 3 · image 180 MB",
        ])
    }

    @Test("leaves out a .localhost address, which answers only on the server")
    func noLocalhost() {
        let status = AppStatus("URL:      https://shop.server.localhost\nURL:      https://shop.com\n")

        #expect(status.urls == ["https://shop.com"])
        #expect(status.fields(now: now).map(\.value) == ["https://shop.com"])
    }

    @Test("an app with no backup says so")
    func noBackup() {
        let status = AppStatus("App:      blog\nVersion:  a1b2c3d\nState:    not running\nBackup:   none\nReplica:  off\n")

        #expect(status.fields(now: now).first { $0.name == "Backup" }?.value == "none yet")
    }

    @Test("the history has its rows, with or without a time to take")
    func readsTheHistory() {
        let rows = HistoryRow.rows("""
        ID  WHEN (UTC)           ACTION                  RESULT     TOOK
        6   2026-10-01 11:58:00  deploy Fix login redirect  running
        5   2026-10-01 11:03:21  deploy 6cff7df          failed     12s
        4   2026-10-01 09:03:02  restore                 succeeded  1m 4s
        """)

        #expect(rows.map(\.id) == ["6", "5", "4"])
        #expect(rows[0].action == "deploy Fix login redirect")
        #expect(rows[0].result == "running")
        #expect(rows[0].took == "")
        #expect(rows[1].took == "12s")
        #expect(rows[1].when(now: now) == "Oct 1 11:03 · 56 min ago")
        #expect(rows[2].outcome == .worked)
        #expect(rows[1].outcome == .failed)
        #expect(rows[0].outcome == .running)
    }

    @Test("a backup is a time, a place, and a size. The live replica is a backup too")
    func readsTheBackups() {
        let rows = BackupRow.rows("""
        20261001T110000Z  server + offsite  48 MB
        20261001T100000Z  offsite
        live              offsite, continuous
        """)

        #expect(rows.map(\.place) == ["server + offsite", "offsite", "offsite, continuous"])
        #expect(rows[0].size == "48 MB")
        #expect(rows[0].when(now: now) == "Oct 1 11:00 UTC · 1 h ago")
        #expect(rows[2].when(now: now) == "live replica")
    }

    @Test("the servers come with their addresses, in the order of the overview")
    func readsTheServers() {
        let output = "  1  https://api.example.com\n* 2  ssh://ubuntu@203.0.113.5\n"

        #expect(Report.addresses(output) == ["https://api.example.com", "ssh://ubuntu@203.0.113.5"])
    }

    @Test("a time says how long ago, in the words of a person")
    func ago() {
        #expect(Report.ago(now.addingTimeInterval(-20), now: now) == "just now")
        #expect(Report.ago(now.addingTimeInterval(-300), now: now) == "5 min ago")
        #expect(Report.ago(now.addingTimeInterval(-7200), now: now) == "2 h ago")
        #expect(Report.ago(now.addingTimeInterval(-259_200), now: now) == "3 days ago")
    }
}
