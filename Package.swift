// swift-tools-version: 5.9
// 5.9 on purpose: Swift 5 language mode, which the AppKit glue is written for.
import PackageDescription

let package = Package(
    name: "Vassago",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "VassagoEngine"),
        .executableTarget(name: "Vassago", dependencies: ["VassagoEngine"]),
        .testTarget(name: "VassagoEngineTests", dependencies: ["VassagoEngine"]),
    ]
)
