// swift-tools-version:6.2
// The iOS app's Apple-model runtime (ios/Runner/AppleModelRuntime.swift,
// symlinked in) behind a JSON-lines stdio protocol, so the Dart eval runner
// (packages/hisab_agents/tool/eval.dart) runs agents on this Mac exactly as
// the phone does.
import PackageDescription

let package = Package(
    name: "apple_model_cli",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "apple-model", path: "Sources/AppleModelCLI"),
    ]
)
