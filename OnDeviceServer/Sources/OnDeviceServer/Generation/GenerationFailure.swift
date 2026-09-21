import Foundation
import FoundationModels

extension APIError {
    /// Maps what a session throws onto the codes OpenAI clients already handle.
    /// Returns nil for errors that are not the model's, such as cancellation.
    ///
    /// Only `LanguageModelError` is mapped. macOS 27 deprecated the older
    /// `LanguageModelSession.GenerationError`, and the system model no longer throws it.
    init?(generationFailure error: Error) {
        switch error {
        case let error as APIError:
            self = error
        case let error as LanguageModelError:
            self.init(error)
        case SystemLanguageModel.Error.assetsUnavailable:
            // The model passed the availability check, then lost its assets: macOS
            // evicts and re-downloads them on its own schedule.
            self = .modelUnavailable(ModelAvailability(.unavailable(.modelNotReady)))
        case let error as LanguageModelSession.ToolCallError:
            self = .internalError("Tool call failed: \(error.underlyingError)")
        case is CancellationError:
            return nil
        default:
            self = .internalError(error.localizedDescription)
        }
    }

    private init(_ error: LanguageModelError) {
        switch error {
        case .contextSizeExceeded(let details):
            self = .contextLengthExceeded(
                "The conversation needs \(details.tokenCount) tokens, but the on-device model's context "
                    + "window holds \(details.contextSize). Shorten the messages or the tool definitions.")
        case .rateLimited(let details):
            self = .rateLimited(resetDate: details.resetDate)
        case .guardrailViolation:
            self = .contentFiltered("The request was blocked by the on-device model's safety guardrails.")
        case .refusal:
            self = .contentFiltered("The on-device model refused to answer this request.")
        case .unsupportedLanguageOrLocale(let details):
            self = .invalidRequest(
                "The on-device model does not support the language '\(details.languageCode.identifier)'.",
                code: "unsupported_language")
        case .unsupportedGenerationGuide(let details):
            self = .invalidRequest(
                "The on-device model cannot enforce a constraint in the schema"
                    + (details.schemaName.map { " '\($0)'" } ?? "") + ": \(details.debugDescription)",
                code: "unsupported_schema")
        case .unsupportedCapability(let details):
            self = .invalidRequest(details.debugDescription, code: "unsupported_capability")
        case .unsupportedTranscriptContent(let details):
            self = .invalidRequest(details.debugDescription, code: "unsupported_content")
        case .timeout:
            self = APIError(
                status: .gatewayTimeout, kind: .api,
                message: "The on-device model timed out.", code: "timeout")
        @unknown default:
            self = .internalError(error.localizedDescription)
        }
    }

    private static func contextLengthExceeded(_ message: String) -> APIError {
        .invalidRequest(message, param: "messages", code: "context_length_exceeded")
    }

    private static func contentFiltered(_ message: String) -> APIError {
        .invalidRequest(message, code: "content_policy_violation")
    }

    // Apple throttles processes without a foreground window, which is what a
    // server mostly is. The message says so because a retry alone does not help.
    private static func rateLimited(resetDate: Date?) -> APIError {
        APIError(
            status: .tooManyRequests, kind: .rateLimit,
            message: "The on-device model is rate limited. macOS throttles apps that are not in the "
                + "foreground; bring the server window to the front, or retry later.",
            code: "rate_limit_exceeded", retryAfter: resetDate)
    }
}
