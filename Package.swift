// swift-tools-version: 6.0
// SwiftPM is the primary build. project.yml (XcodeGen) is a secondary path for Xcode users.
import PackageDescription

let package = Package(
    name: "ScreenCap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenCap", targets: ["ScreenCap"]),
        .library(name: "ScreenCapKit", targets: ["ScreenCapKit"])
    ],
    dependencies: [
        // Global shortcuts plus a SwiftUI recorder; handles Carbon hot keys and conflict checks.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.10.0"),
        // Signed auto-updates from the GitHub Releases appcast (PLAN §2).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ScreenCap",
            dependencies: ["ScreenCapKit", "KeyboardShortcuts", .product(name: "Sparkle", package: "Sparkle")],
            path: "App",
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .target(
            name: "ScreenCapKit",
            path: "Packages/ScreenCapKit/Sources/ScreenCapKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreImage")
            ]
        ),
        .testTarget(
            name: "ScreenCapKitTests",
            dependencies: ["ScreenCapKit"],
            path: "Packages/ScreenCapKit/Tests/ScreenCapKitTests"
        ),
        // Pure app-side logic (menu model, shortcut defaults, countdown, selection math).
        .testTarget(
            name: "ScreenCapTests",
            dependencies: ["ScreenCap", "ScreenCapKit"],
            path: "Tests/ScreenCapTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
