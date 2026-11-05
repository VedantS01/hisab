import Flutter
import Foundation
import FoundationModels

/// AppleModelRuntime on the `hisab/apple_model` channel, for
/// packages/hisab_agents' ChannelRuntime. Requests and replies cross as JSON
/// text; a tool the model calls is run in Dart through the same channel
/// (`tool` {name, arguments} → result text).
///
/// The cloud model is used only when Info.plist's HisabCloudModel is true,
/// which is set together with the com.apple.developer.private-cloud-compute
/// entitlement — without it, merely constructing the model fails.
enum AppleModelChannel {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "hisab/apple_model", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            guard #available(iOS 26.0, *) else {
                return result(call.method == "status" ? "{\"onDevice\":\"osTooOld\",\"cloud\":\"osTooOld\"}" : nil)
            }
            let runtime = AppleModelRuntime(cloudEntitled: cloudEntitled) { name, arguments in
                try await callTool(channel, name: name, arguments: arguments)
            }
            switch call.method {
            case "status":
                result(json(runtime.status()))
            case "respond":
                guard let text = call.arguments as? String,
                      let request = try? JSONDecoder().decode(AppleModelRuntime.Request.self, from: Data(text.utf8)) else {
                    return result(FlutterError(code: "badRequest", message: "could not decode request", details: nil))
                }
                Task {
                    do {
                        let reply = try await runtime.respond(request)
                        let data = try JSONEncoder().encode(reply)
                        result(String(data: data, encoding: .utf8))
                    } catch let failure as AppleModelRuntime.Failure {
                        result(FlutterError(code: failure.code, message: failure.message, details: nil))
                    } catch {
                        result(FlutterError(code: "failed", message: "\(error)", details: nil))
                    }
                }
            case "showQuotaOptions":
                if cloudEntitled, #available(iOS 27.0, *) {
                    PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static var cloudEntitled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "HisabCloudModel") as? Bool ?? false
    }

    @available(iOS 26.0, *) @MainActor
    private static func callTool(_ channel: FlutterMethodChannel, name: String, arguments: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            channel.invokeMethod("tool", arguments: ["name": name, "arguments": arguments]) { reply in
                if let error = reply as? FlutterError {
                    continuation.resume(throwing: AppleModelRuntime.Failure(
                        code: "tool", message: "\(name): \(error.message ?? error.code)"))
                } else {
                    continuation.resume(returning: reply as? String ?? "")
                }
            }
        }
    }

    private static func json(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
