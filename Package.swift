// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notchly",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Notchly",
            resources: [.process("Resources")]),
    ]
)
