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
    targets: [
        .executableTarget(
            name: "ScreenCap",
            dependencies: ["ScreenCapKit"],
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
        )
    ],
    swiftLanguageModes: [.v6]
)
