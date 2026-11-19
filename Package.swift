// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipText",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClipText", targets: ["ClipText"])],
    targets: [
        .executableTarget(name: "ClipText")
    ]
)
