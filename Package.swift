// swift-tools-version: 6.0
import PackageDescription

// ChasenKit is what the app knows: the overview of your servers, the state of
// the menu bar, and the news between two overviews. Foundation only, so its
// tests run anywhere. ChasenUI draws it. Chasen is the app, and snapshot
// renders the views and the icon to PNG files, for the build and for CI.
let package = Package(
    name: "chasen-mac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ChasenKit"),
        .target(name: "ChasenUI", dependencies: ["ChasenKit"]),
        .executableTarget(name: "Chasen", dependencies: ["ChasenKit", "ChasenUI"]),
        .executableTarget(name: "snapshot", dependencies: ["ChasenKit", "ChasenUI"]),
        .testTarget(name: "ChasenKitTests", dependencies: ["ChasenKit"]),
    ],
    swiftLanguageModes: [.v5]
)
