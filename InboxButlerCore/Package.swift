// swift-tools-version: 5.9
import PackageDescription

// InboxButlerCore: all shared, UI-free logic for Inbox Butler.
// Used by the Swift Playgrounds app (InboxButler.swiftpm) and by Xcode targets
// (including the widget extension).
let package = Package(
    name: "InboxButlerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InboxButlerCore", targets: ["InboxButlerCore"])
    ],
    targets: [
        .target(name: "InboxButlerCore"),
        .testTarget(name: "InboxButlerCoreTests", dependencies: ["InboxButlerCore"])
    ]
)
