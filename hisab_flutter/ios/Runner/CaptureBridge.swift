import Flutter
import Foundation

/// Runs Hisab's Dart capture code (lib/capture_entry.dart) for the Shortcuts
/// action. An automation fires with the app closed and no UI, so the alert
/// goes to a headless engine of its own rather than the app's. That engine is
/// kept for the life of the process: bank alerts arrive in bursts, and the
/// on-device reader takes a moment to load.
@MainActor
final class CaptureBridge {
    static let shared = CaptureBridge()

    /// The app's engine, once the UI has started. Its drift streams cannot see
    /// another engine's writes, so it is told to re-read after a capture.
    var appMessenger: FlutterBinaryMessenger?

    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var ready = false
    private var waiting: [CheckedContinuation<Bool, Never>] = []

    /// What Shortcuts says back: the Dart intake's sentence, or a failure line
    /// when the engine could not start or answered with nothing.
    func ingest(text: String, note: String?) async -> String {
        let failed = "Hisab couldn't save that alert. Nothing was stored."
        guard await start(), let channel else { return failed }
        let reply: Any? = await withCheckedContinuation { continuation in
            channel.invokeMethod("ingest", arguments: ["text": text, "note": note as Any]) {
                continuation.resume(returning: $0)
            }
        }
        guard let map = reply as? [String: Any], let dialog = map["dialog"] as? String else {
            return failed
        }
        if map["outcome"] as? String == "logged", let appMessenger {
            FlutterMethodChannel(name: "hisab/app", binaryMessenger: appMessenger)
                .invokeMethod("dataChanged", arguments: nil)
        }
        return dialog
    }

    /// True once Dart has installed its handler; false if it never does
    /// within 20 seconds, so a broken engine fails the action instead of
    /// hanging the automation.
    private func start() async -> Bool {
        if ready { return true }
        if engine == nil {
            let engine = FlutterEngine(name: "hisab.capture", project: nil, allowHeadlessExecution: true)
            engine.run(withEntrypoint: "captureMain", libraryURI: "package:hisab/capture_entry.dart")
            GeneratedPluginRegistrant.register(with: engine)
            // After `run` (the engine refuses handlers before it), and in the
            // same main-thread turn, so Dart's "ready" cannot arrive first.
            let channel = FlutterMethodChannel(name: "hisab/capture", binaryMessenger: engine.binaryMessenger)
            channel.setMethodCallHandler { [weak self] call, result in
                guard call.method == "ready" else { return result(FlutterMethodNotImplemented) }
                result(nil)
                MainActor.assumeIsolated { self?.finishStarting(true) }
            }
            self.engine = engine
            self.channel = channel
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.ready else { return }
                    self.engine?.destroyContext()
                    self.engine = nil
                    self.channel = nil
                    self.finishStarting(false)
                }
            }
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func finishStarting(_ succeeded: Bool) {
        ready = succeeded
        let resumed = waiting
        waiting = []
        resumed.forEach { $0.resume(returning: succeeded) }
    }
}
