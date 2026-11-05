import Foundation
import FoundationModels

/// Runs one agent request on Apple's language models: Private Cloud Compute
/// when the build holds the entitlement and the service is up, the on-device
/// model otherwise — and the on-device model again when a cloud request fails
/// for a reason that isn't the request's own (network, service, limits).
///
/// Agents (instructions, JSON schemas, tools) are defined in Dart
/// (packages/hisab_agents); this file only runs them. It is shared unchanged
/// by the iOS channel (AppleModelChannel.swift) and the macOS eval CLI
/// (tool/apple_model_cli), so evals exercise the code the phone runs.
@available(iOS 26.0, macOS 26.0, *)
struct AppleModelRuntime {
    struct Request: Decodable {
        var instructions: String
        var prompt: String
        /// JSON Schema of the reply; absent for a plain-text reply.
        var schema: GenerationSchema?
        var tools: [ToolSpec]?
        /// light | moderate | deep — cloud only; the on-device model doesn't reason.
        var reasoning: String?
        /// auto (default) | cloud | onDevice
        var model: String?
        /// Always the most likely token: for labelling, where variety is noise.
        var greedy: Bool?
        /// The request transforms the user's own content (statements, alerts),
        /// which the on-device model's default guardrails often refuse.
        var transform: Bool?
    }

    struct ToolSpec: Decodable {
        var name: String
        var description: String
        var parameters: GenerationSchema
    }

    struct Reply: Encodable {
        /// JSON text when the request had a schema, else the model's text.
        var content: String
        /// cloud | onDevice
        var model: String
        /// Why a cloud request fell back: network | unavailable | rateLimited | quota.
        var fallback: String?
    }

    /// A request the models couldn't serve. Codes: unavailable, context,
    /// refused, language, timeout, quota, failed.
    struct Failure: Error {
        var code: String
        var message: String
    }

    /// Whether this build carries com.apple.developer.private-cloud-compute.
    /// Without it the cloud model must not even be constructed.
    let cloudEntitled: Bool
    /// Runs a tool in Dart: name and JSON arguments in, the result as text out.
    let callTool: @Sendable (String, String) async throws -> String

    /// Each model's availability, for Dart to decide what to offer.
    func status() -> [String: String] {
        var status = ["onDevice": Self.describe(SystemLanguageModel.default.availability)]
        if !cloudEntitled {
            status["cloud"] = "notEntitled"
        } else if #available(iOS 27.0, macOS 27.0, *) {
            let cloud = PrivateCloudComputeLanguageModel()
            switch cloud.availability {
            case .available: status["cloud"] = "available"
            case .unavailable(.deviceNotEligible): status["cloud"] = "deviceNotEligible"
            case .unavailable(.systemNotReady): status["cloud"] = "systemNotReady"
            case .unavailable: status["cloud"] = "unavailable"
            }
            if cloud.quotaUsage.isLimitReached {
                status["quota"] = "reached"
            } else if case .belowLimit(let info) = cloud.quotaUsage.status, info.isApproachingLimit {
                status["quota"] = "approaching"
            }
        } else {
            status["cloud"] = "osTooOld"
        }
        return status
    }

    func respond(_ request: Request) async throws -> Reply {
        let tools: [any Tool] = (request.tools ?? []).map {
            DartTool(name: $0.name, description: $0.description, parameters: $0.parameters, run: callTool)
        }
        var fallback: String?
        if request.model != "onDevice", cloudEntitled, #available(iOS 27.0, macOS 27.0, *) {
            let cloud = PrivateCloudComputeLanguageModel()
            if cloud.isAvailable {
                do {
                    let session = LanguageModelSession(model: cloud, tools: tools, instructions: request.instructions)
                    let content = try await Self.generate(session, request, reasoning: Self.reasoning(request.reasoning))
                    return Reply(content: content, model: "cloud", fallback: nil)
                } catch let error as PrivateCloudComputeLanguageModel.Error {
                    switch error {
                    case .networkFailure: fallback = "network"
                    case .quotaLimitReached: fallback = "quota"
                    case .serviceUnavailable: fallback = "unavailable"
                    @unknown default: fallback = "unavailable"
                    }
                } catch LanguageModelError.rateLimited {
                    fallback = "rateLimited"
                } catch {
                    throw Self.failure(error)
                }
                if request.model == "cloud" {
                    throw Failure(code: fallback == "quota" ? "quota" : "unavailable", message: fallback ?? "")
                }
            } else {
                fallback = "unavailable"
            }
        }
        guard SystemLanguageModel.default.isAvailable else {
            throw Failure(code: "unavailable", message: Self.describe(SystemLanguageModel.default.availability))
        }
        do {
            let model = request.transform == true
                ? SystemLanguageModel(guardrails: .permissiveContentTransformations) : .default
            let session = LanguageModelSession(model: model, tools: tools, instructions: request.instructions)
            let content = try await Self.generate(session, request, reasoning: nil)
            return Reply(content: content, model: "onDevice", fallback: fallback)
        } catch {
            throw Self.failure(error)
        }
    }

    private static func generate(
        _ session: LanguageModelSession, _ request: Request, reasoning: Any?
    ) async throws -> String {
        let options = request.greedy == true ? GenerationOptions(sampling: .greedy) : GenerationOptions()
        if #available(iOS 27.0, macOS 27.0, *), let level = reasoning as? ContextOptions.ReasoningLevel {
            let context = ContextOptions(reasoningLevel: level)
            if let schema = request.schema {
                return try await session.respond(
                    to: request.prompt, schema: schema, options: options, contextOptions: context
                ).content.jsonString
            }
            return try await session.respond(to: request.prompt, options: options, contextOptions: context).content
        }
        if let schema = request.schema {
            return try await session.respond(to: request.prompt, schema: schema, options: options).content.jsonString
        }
        return try await session.respond(to: request.prompt, options: options).content
    }

    private static func reasoning(_ name: String?) -> Any? {
        guard #available(iOS 27.0, macOS 27.0, *) else { return nil }
        switch name {
        case "light": return ContextOptions.ReasoningLevel.light
        case "moderate": return ContextOptions.ReasoningLevel.moderate
        case "deep": return ContextOptions.ReasoningLevel.deep
        default: return nil
        }
    }

    private static func failure(_ error: Error) -> Failure {
        if let failure = error as? Failure { return failure }
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return Failure(code: "context", message: "\(error)")
            case .guardrailViolation, .refusal: return Failure(code: "refused", message: "\(error)")
            case .unsupportedLanguageOrLocale: return Failure(code: "language", message: "\(error)")
            case .timeout: return Failure(code: "timeout", message: "\(error)")
            default: return Failure(code: "failed", message: "\(error)")
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return Failure(code: "context", message: "\(error)")
            case .guardrailViolation, .refusal: return Failure(code: "refused", message: "\(error)")
            case .unsupportedLanguageOrLocale: return Failure(code: "language", message: "\(error)")
            default: return Failure(code: "failed", message: "\(error)")
            }
        }
        return Failure(code: "failed", message: "\(error)")
    }

    private static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: return "available"
        case .unavailable(.deviceNotEligible): return "deviceNotEligible"
        case .unavailable(.appleIntelligenceNotEnabled): return "appleIntelligenceNotEnabled"
        case .unavailable(.modelNotReady): return "modelNotReady"
        case .unavailable: return "unavailable"
        }
    }
}

/// A tool whose work happens in Dart: the model's arguments go across as JSON,
/// the result comes back as text the model reads.
@available(iOS 26.0, macOS 26.0, *)
private struct DartTool: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    let run: @Sendable (String, String) async throws -> String

    @concurrent func call(arguments: GeneratedContent) async throws -> String {
        try await run(name, arguments.jsonString)
    }
}
