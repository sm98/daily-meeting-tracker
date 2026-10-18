// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarCalendar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MenuBarCalendar",
            path: "Sources/MenuBarCalendar"
        )
    ]
)
