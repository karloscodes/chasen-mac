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
//                                   ImageRenderer draws SwiftUI only: a native
//                                   field, like the address of the login, is a
//                                   yellow box here.

let usage = "Usage: snapshot icon <file.png> <size> | snapshot panels <directory>\n"

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

let shop = Overview.App(app: "shop", state: "Up 3 hours (healthy)", version: "1.4.2", domains: ["shop.example.com"])
let blog = Overview.App(app: "blog", state: "Up 2 days", version: "3f9a2c1", domains: ["blog.example.com"])
let admin = Overview.App(app: "admin", state: "Up 5 days", version: "0.9.1", listen: "127.0.0.1:8080")
let analytics = Overview.App(app: "fusionaly", state: "Up 5 days (healthy)", version: "latest", domains: ["analytics.example.com"])
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

@MainActor
func render(_ view: some View, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    write(renderer.cgImage, to: path)
}

@MainActor
func panels(into directory: String) {
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let states: [(String, Overview?, String?, Double)] = [
        ("calm", calm(), nil, 0),
        ("deploy", busy(), nil, 0.7),
        ("trouble", trouble(), nil, 0),
        ("login", Overview(servers: []), nil, 0),
        ("waiting", nil, nil, 0),
        ("stopped", nil, "Error: the credentials file is not readable", 0),
    ]
    for (name, overview, problem, sway) in states {
        render(Panel(overview: overview, problem: problem, sway: sway, about: "0.1.0 · chasen 0.13.0", atLogin: .constant(true), actions: .none, now: now), to: "\(directory)/panel-\(name).png")
    }
    render(MenuBars(), to: "\(directory)/menu-bar.png")
    write(Mark.appIcon(size: 512), to: "\(directory)/icon.png")
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
    default:
        FileHandle.standardError.write(Data(usage.utf8))
        exit(2)
    }
}
