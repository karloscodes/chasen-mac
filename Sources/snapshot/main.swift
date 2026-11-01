import AppKit
import ChasenKit
import ChasenUI
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// snapshot icon <file.png> <size>   the app icon, for bin/build
// snapshot panels <directory>       the panel in each state, with sample
//                                   servers, and the menu bar icon: PNG files
//                                   to see the app without a Mac. CI keeps them.
//                                   The window of the menu bar gives the panel
//                                   the material of macOS: here a plain color
//                                   stands in for it.
// snapshot dashboard <directory>    the window in each part, with sample
//                                   servers, in a real window out of sight.

let usage = "Usage: snapshot icon <file.png> <size> | snapshot panels <directory> | snapshot dashboard <directory>\n"

func write(_ image: CGImage?, to path: String) {
    guard let image, let file = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("snapshot: cannot write \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(file, image, nil)
    CGImageDestinationFinalize(file)
}

let now = Date(timeIntervalSince1970: 1_793_440_000)
let started = ISO8601DateFormatter().string(from: now.addingTimeInterval(-14))

let shop = Overview.App(app: "shop", state: "Up 3 hours (healthy)", version: "1.4.2", domains: ["shop.server.localhost", "shop.example.com"])
let blog = Overview.App(app: "blog", state: "Up 2 days", version: "3f9a2c1", domains: ["blog.example.com"])
let admin = Overview.App(app: "private-sample", state: "Up 5 days", version: "0.9.1", listen: "127.0.0.1:8080")
let analytics = Overview.App(app: "fusionaly", state: "Up 5 days (healthy)", version: "2.13.0-rc.1", domains: ["analytics.long-domain-example.com"])
let chat = Overview.App(app: "campfire", state: "Up 9 hours", version: "main", domains: ["chat.example.com"])

func calm() -> Overview {
    Overview(servers: [
        .init(name: "example.com", apps: [shop, blog, admin, analytics]),
        .init(name: "203.0.113.5", apps: [chat]),
    ])
}

func busy() -> Overview {
    var deploying = shop
    deploying.running = "deploy Fix the login redirect"
    deploying.since = started
    return Overview(servers: [
        .init(name: "example.com", apps: [deploying, blog, admin, analytics]),
        .init(name: "203.0.113.5", apps: [chat]),
    ])
}

func trouble() -> Overview {
    var down = blog
    down.up = false
    down.state = "Exited (1) 3 minutes ago"
    return Overview(servers: [
        .init(name: "example.com", apps: [shop, down, admin, analytics], alerts: [
            .init(error: true, what: "the disk is 93% full: 2.8 GB free", fix: "docker image prune -a removes the images that no container uses. Or make the disk larger at your provider."),
        ]),
        .init(name: "203.0.113.5", error: "ssh: connect to host 203.0.113.5 port 22: Operation timed out"),
    ])
}

/// Draws a view through AppKit, so a native field or button shows too.
@MainActor
func render(_ view: some View, dark: Bool = true, to path: String) {
    let scheme: ColorScheme = dark ? .dark : .light
    let host = NSHostingView(rootView: view.background(Color(white: dark ? 0.16 : 0.93)).environment(\.colorScheme, scheme))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    write(bitmap.cgImage, to: path)
}

@MainActor
func panels(into directory: String) {
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let states: [(String, Overview?, String?, Double, LoginState)] = [
        ("calm", calm(), nil, 0, .closed),
        ("deploy", busy(), nil, 0.7, .closed),
        ("trouble", trouble(), nil, 0, .closed),
        ("login", Overview(servers: []), nil, 0, .closed),
        ("login-running", Overview(servers: []), nil, 0, .running(["chasen-server is not on this server yet. Installing it.", "Setting up the server."])),
        ("login-failed", calm(), nil, 0, .failed(["Error: cannot log in to the server through SSH: Permission denied (publickey)."])),
        ("waiting", nil, nil, 0, .closed),
        ("stopped", nil, "Error: the credentials file is not readable", 0, .closed),
    ]
    func panel(_ state: (String, Overview?, String?, Double, LoginState)) -> some View {
        Panel(overview: state.1, problem: state.2, sway: state.3, login: state.4, about: "0.1.0 · chasen 0.13.0", atLogin: .constant(true), actions: .none, now: now)
    }
    for state in states {
        render(panel(state), to: "\(directory)/panel-\(state.0).png")
    }
    render(panel(states[0]), dark: false, to: "\(directory)/panel-calm-light.png")
    Look.shared.theme = .monochrome
    render(panel(states[2]), to: "\(directory)/panel-trouble-monochrome.png")
    Look.shared.theme = .chasen
    func silent(_ why: String, said: [String]) -> some View {
        let error = "cannot reach the server through SSH (ssh://ubuntu@203.0.113.5): \(why). Does ssh log in to it, and does it have chasen-server 0.6 or newer?"
        return Panel(overview: Overview(servers: [.init(name: "example.com", error: error)]), problem: nil, sway: 0, said: said, about: "0.1.0 · chasen 0.13.0", atLogin: .constant(true), actions: .none, now: now)
    }
    render(silent("EOF", said: ["ubuntu@203.0.113.5: Permission denied (publickey)."]), to: "\(directory)/panel-no-answer.png")
    render(silent("context deadline exceeded", said: []), to: "\(directory)/panel-key-waiting.png")
    render(MenuBars(), to: "\(directory)/menu-bar.png")
    write(Mark.appIcon(size: 512), to: "\(directory)/icon.png")
}

func stamp(_ seconds: TimeInterval) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: now.addingTimeInterval(seconds))
}

func fleet() -> Overview {
    Overview(servers: [
        .init(name: "example.com", apps: [
            .init(app: "shop", state: "Up 3 hours (healthy)", version: "1.4.2", domains: ["shop.example.com"], jobs: "Up 3 hours", databases: 2, backup: stamp(-2400), replica: "live"),
            .init(app: "blog", state: "Up 2 days", version: "3f9a2c1d5e8b", domains: ["blog.example.com"], databases: 1, backup: stamp(-2400), replica: "live"),
            .init(app: "analytics", state: "Up 5 hours", version: "2.13.0-rc.1", running: "deploy Fix the chart", since: started, domains: ["stats.example.com"], databases: 1, backup: stamp(-2400), replica: "live"),
            .init(app: "admin", state: "Up 6 days", version: "0.9.1", listen: "127.0.0.1:8080", databases: 1, backup: stamp(-9000), replica: "off"),
            .init(app: "mail", state: "Exited (1) 3 minutes ago", up: false, version: "1.2.0", domains: ["mail.example.com"], databases: 0, backup: "off", replica: "off"),
        ], alerts: [
            .init(error: true, what: "mail is down: its container is exited", fix: "chasen -a mail logs shows why, and chasen -a mail restart starts it again."),
            .init(error: false, what: "SSH accepts passwords: a bot can guess one", fix: "Log in with a key, then add PasswordAuthentication no to /etc/ssh/sshd_config and run: systemctl reload ssh"),
        ]),
        .init(name: "203.0.113.5", error: "ssh: connect to host 203.0.113.5 port 22: Operation timed out"),
    ])
}

/// A real window out of sight, with its sidebar and its toolbar.
@MainActor
func capture(_ view: some View, dark: Bool, to path: String) {
    let window = Dashboard.window(view)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
    window.orderFrontRegardless()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
    let frame = (window.attachedSheet ?? window).contentView!.superview!
    let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
    frame.cacheDisplay(in: frame.bounds, to: bitmap)
    write(bitmap.cgImage, to: path)
    window.close()
}

@MainActor
func dashboards(into directory: String) {
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let load = ServerLoad("""
    Load:     0.42 0.38 0.31 (4 cores, amd64)
    Memory:   4.6 GB of 7.6 GB (61%)
    Disk:     34 GB of 76 GB (45%)
    Bucket:   my-backups
    API:      SSH only: not on the web
    """)
    let status = AppStatus("""
    App:      shop
    Version:  1.4.2
    State:    Up 3 hours (healthy)
    Disk:     data 212 MB · backups 480 MB in 7 · image 180 MB
    URL:      https://shop.example.com
    URL:      https://shop.com
    Backup:   \(stamp(-2400))
    Replica:  live
    """)
    func moment(_ seconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: now.addingTimeInterval(seconds))
    }
    let history = HistoryRow.rows("""
    ID  WHEN (UTC)           ACTION                     RESULT     TOOK
    48  \(moment(-12))  deploy Fix login redirect  running
    47  \(moment(-3600))  deploy Add the wish list    succeeded  48s
    46  \(moment(-7400))  backup                     succeeded  3s
    45  \(moment(-90000))  deploy Bump rails           failed     12s
    44  \(moment(-180000))  restart                    succeeded  6s
    """)
    let backups = BackupRow.rows("""
    \(stamp(-2400))  server + offsite  48 MB
    \(stamp(-6000))  server + offsite  48 MB
    \(stamp(-9600))  offsite
    live              offsite, continuous
    """)
    let logs = (0..<60).map { "2026-10-31T14:\(10 + $0 / 2):0\($0 % 10)Z GET /products/\($0) 200 in 12ms" }
    let shopPlace = Place.app(server: "example.com", app: "shop")
    let facts: [Place: Facts] = [shopPlace: Facts(status: status, history: history, backups: backups, domains: ["shop.example.com", "shop.com", "shop.server.localhost"], logs: logs)]
    func window(_ place: Place, _ tab: AppTab, entry: Entry? = nil) -> some View {
        Dashboard(overview: fleet(), problem: nil, sway: 0, loads: ["example.com": load], facts: facts, place: .constant(place), tab: .constant(tab), entry: .constant(entry), actions: .none, now: now)
    }
    capture(window(.server("example.com"), .overview), dark: true, to: "\(directory)/dashboard-map.png")
    capture(window(.server("example.com"), .overview), dark: false, to: "\(directory)/dashboard-map-light.png")
    capture(window(.server("203.0.113.5"), .overview), dark: true, to: "\(directory)/dashboard-silent.png")
    for tab in AppTab.allCases {
        capture(window(shopPlace, tab), dark: true, to: "\(directory)/dashboard-\(tab.rawValue).png")
    }
    for theme in [ScreenTheme.monochrome, .terminal] {
        Look.shared.theme = theme
        capture(window(.server("example.com"), .overview), dark: true, to: "\(directory)/dashboard-map-\(theme.rawValue).png")
        capture(window(.server("example.com"), .overview), dark: false, to: "\(directory)/dashboard-map-\(theme.rawValue)-light.png")
        capture(window(shopPlace, .history), dark: true, to: "\(directory)/dashboard-history-\(theme.rawValue).png")
    }
    Look.shared.theme = .chasen
    capture(window(shopPlace, .history, entry: Entry(id: "47", title: "deploy Add the wish list", command: "history -a shop 47", lines: ["Pulling ghcr.io/you/shop:1.4.2", "Starting the new version", "The app answers /up", "The proxy points to the new version"])), dark: true, to: "\(directory)/dashboard-entry.png")
}

/// The menu bar icon in each mood, on a light bar and a dark one, as large
/// as 4 Retina pixels for each cell.
struct MenuBars: View {
    let moods: [(String, Mood.Level, Double)] = [("calm", .calm, 0), ("warning", .warning, 0), ("trouble", .trouble, 0), ("deploy", .calm, -1), ("deploy", .calm, 1)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar(dark: false)
            bar(dark: true)
        }
    }

    func bar(dark: Bool) -> some View {
        HStack(spacing: 28) {
            ForEach(moods.indices, id: \.self) { i in
                VStack(spacing: 8) {
                    Canvas { context, size in
                        context.withCGContext { cg in
                            var color = Mark.menuColor(moods[i].1)
                            if dark && moods[i].1 != .trouble {
                                // A template image is white on a dark bar.
                                color = CGColor(gray: 1, alpha: color.alpha)
                            }
                            Mark.draw(in: cg, at: .zero, cell: 4, color: color, sway: moods[i].2)
                        }
                    }
                    .frame(width: CGFloat(Mark.width) * 4, height: CGFloat(Mark.height) * 4)
                    Text(moods[i].0).font(.system(size: 11, design: .monospaced)).foregroundStyle(dark ? .white : .black)
                }
            }
        }
        .padding(24)
        .background(dark ? Color(white: 0.16) : Color(white: 0.93))
    }
}

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    switch arguments.count > 1 ? arguments[1] : "" {
    case "icon" where arguments.count == 4:
        write(Mark.appIcon(size: Int(arguments[3]) ?? 1024), to: arguments[2])
    case "panels" where arguments.count == 3:
        panels(into: arguments[2])
    case "dashboard" where arguments.count == 3:
        dashboards(into: arguments[2])
    default:
        FileHandle.standardError.write(Data(usage.utf8))
        exit(2)
    }
}
