// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Enoki",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Enoki", targets: ["Enoki"]),
        .library(name: "EnokiCore", targets: ["EnokiCore"]),
    ],
    targets: [
        // AppKit に依存しない純ロジック（テスト対象）
        .target(
            name: "EnokiCore",
            path: "Sources/EnokiCore"
        ),
        // 実行ターゲット（AppKit）
        .executableTarget(
            name: "Enoki",
            dependencies: ["EnokiCore"],
            path: "Sources/Enoki",
            resources: [
                .copy("Resources/DefaultSkin"),
                .copy("Resources/AppIcon"),
                .copy("Resources/DialogueText"),
            ]
        ),
        .testTarget(
            name: "EnokiCoreTests",
            dependencies: ["EnokiCore"],
            path: "Tests/EnokiCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
