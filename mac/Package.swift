// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Netmon",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Netmon",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Netmon",
            exclude: [
                "App/Info.plist",
                "App/Netmon.entitlements",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Network"),
            ]
        ),
    ]
)
