// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSystemMonitor",
    platforms: [
        .macOS(.v13) // MenuBarExtra / SwiftUI moderne
    ],
    targets: [
        .executableTarget(
            name: "MacSystemMonitor",
            path: "Sources/MacSystemMonitor"
        )
    ]
)
