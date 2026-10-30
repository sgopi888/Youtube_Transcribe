// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "YTScribe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "YTScribeCore"),
        .executableTarget(name: "YTScribe", dependencies: ["YTScribeCore"]),
        .testTarget(name: "YTScribeCoreTests", dependencies: ["YTScribeCore"]),
    ]
)
