import Flutter
import UIKit

/// Files opened or shared into Hisab ("Open in…", the share sheet's "Copy to
/// Hisab") and hisab:// links, handed to Dart (lib/services/incoming_router.dart).
///
/// A cold launch delivers them while the scene connects, before Dart has a
/// handler, so they queue until Dart asks for them once; after that each one
/// is pushed as it arrives.
final class IncomingRouter: NSObject, FlutterSceneLifeCycleDelegate {
    static let shared = IncomingRouter()

    private var channel: FlutterMethodChannel?
    private var pending: [[String: String]] = {
        #if DEBUG
        // `simctl launch … com.vedants.hisab --tab 3`: a screen tour without
        // the "Open in Hisab?" prompt a hisab:// link gets on the simulator.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--tab"), i + 1 < args.count {
            return [["kind": "link", "url": "hisab://tab/\(args[i + 1])"]]
        }
        #endif
        return []
    }()
    private var dartListening = false

    func attach(to registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "hisab/incoming", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "pending", let self else { return result(FlutterMethodNotImplemented) }
            self.dartListening = true
            result(self.pending)
            self.pending = []
        }
        self.channel = channel
        registrar.addSceneDelegate(self)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
        guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else { return false }
        receive(contexts)
        return true
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
        receive(URLContexts)
        return true
    }

    private func receive(_ contexts: Set<UIOpenURLContext>) {
        for url in contexts.map(\.url) {
            let item: [String: String]
            if url.isFileURL {
                guard let staged = stage(url) else { continue }
                item = ["kind": "file", "path": staged.path, "name": url.lastPathComponent]
            } else if url.scheme == "hisab" {
                item = ["kind": "link", "url": url.absoluteString]
            } else {
                continue
            }
            if dartListening {
                channel?.invokeMethod("open", arguments: item)
            } else {
                pending.append(item)
            }
        }
    }

    /// A private copy Dart can read and delete: an "Open in place" URL points
    /// into another app's storage and is readable only inside a
    /// security-scoped access window.
    private func stage(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            NSLog("hisab-incoming: could not stage an opened file (\(type(of: error)))")
            return nil
        }
    }
}
