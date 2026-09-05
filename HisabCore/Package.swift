// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HisabCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HisabCore", targets: ["HisabCore"])
    ],
    targets: [
        .target(name: "HisabCore"),
        .testTarget(name: "HisabCoreTests", dependencies: ["HisabCore"])
    ]
)
