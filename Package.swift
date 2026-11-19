// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Glow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glow", targets: ["GlowApp"])],
    targets: [
        .executableTarget(name: "GlowApp"),
        .testTarget(name: "GlowAppTests", dependencies: ["GlowApp"])
    ]
)
