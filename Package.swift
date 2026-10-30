// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacDownloader",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacDownloader",
            path: "Sources/MacDownloader",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MacDownloaderTests",
            dependencies: ["MacDownloader"],
            path: "Tests/MacDownloaderTests"
        ),
    ]
)
