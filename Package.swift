// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sphere",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Sphere", targets: ["SphereApp"]),
        .executable(name: "sphere-cli", targets: ["SphereCLI"]),
        .library(name: "SphereCore", targets: ["SphereCore"]),
        .library(name: "SphereLLM", targets: ["SphereLLM"]),
        .library(name: "SphereMCP", targets: ["SphereMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "SphereCore",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "SphereLLM",
            dependencies: ["SphereCore"]
        ),
        .target(
            name: "SphereMCP",
            dependencies: ["SphereCore"]
        ),
        .target(
            name: "SphereTools",
            dependencies: ["SphereCore", "SphereMCP"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .target(
            name: "SphereScreen",
            dependencies: ["SphereCore"],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "SphereKnowledge",
            dependencies: ["SphereCore"]
        ),
        .target(
            name: "SphereSpeech",
            dependencies: ["SphereCore"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
            ]
        ),
        .target(
            name: "SphereRuntime",
            dependencies: [
                "SphereCore",
                "SphereLLM",
                "SphereMCP",
                "SphereTools",
                "SphereScreen",
                "SphereKnowledge",
            ]
        ),
        .executableTarget(
            name: "SphereApp",
            dependencies: [
                "SphereRuntime",
                "SphereCore",
                "SphereLLM",
                "SphereMCP",
                "SphereTools",
                "SphereScreen",
                "SphereKnowledge",
                "SphereSpeech",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "SphereCLI",
            dependencies: [
                "SphereRuntime",
                "SphereCore",
                "SphereLLM",
                "SphereMCP",
                "SphereTools",
                "SphereScreen",
                "SphereKnowledge",
            ]
        ),
        .testTarget(
            name: "SphereCoreTests",
            dependencies: ["SphereCore", "SphereLLM", "SphereTools", "SphereMCP"]
        ),
    ]
)
