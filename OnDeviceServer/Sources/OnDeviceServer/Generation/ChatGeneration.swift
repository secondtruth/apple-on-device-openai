import Foundation
import FoundationModels

/// One chat completion, from a validated request to the model's output.
///
/// Streaming and non-streaming responses consume the same event sequence, so
/// both paths share validation, option mapping and error mapping.
struct ChatGeneration: Sendable {
    enum Event: Sendable {
        case textDelta(String)
        /// Always the last event.
        case completed(Completion)
    }

    struct Completion: Sendable {
        /// The full text. Authoritative over the concatenated deltas, because the
        /// model may revise text it has already streamed.
        var content: String
        var finishReason: FinishReason
        var usage: TokenUsage
    }

    let model: OnDeviceModel
    private let conversation: Conversation
    private let options: GenerationOptions
    private let responseTokenLimit: Int?

    /// Validates the whole request, so that everything a client got wrong is
    /// reported before the model is involved.
    init(_ request: ChatCompletionRequest) throws(APIError) {
        try Self.rejectUnsupportedParameters(of: request)
        model = try OnDeviceModel.named(request.model)
        conversation = try Conversation(messages: request.messages)
        options = try Self.options(of: request)
        responseTokenLimit = request.responseTokenLimit
    }

    func events() -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(yieldingTo: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError(generationFailure: error) ?? error)
                }
            }
            // Dropping the stream is how a disconnected client stops the model.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Running the session

    private func run(yieldingTo continuation: AsyncThrowingStream<Event, Error>.Continuation) async throws {
        let session = LanguageModelSession(model: model.languageModel, transcript: conversation.transcript)

        var content = ""
        for try await snapshot in session.streamResponse(to: Prompt(conversation.prompt), options: options) {
            if snapshot.content.hasPrefix(content) {
                continuation.yield(.textDelta(String(snapshot.content.dropFirst(content.count))))
            }
            content = snapshot.content
        }
        continuation.yield(.completed(completion(of: session, content: content)))
    }

    private func completion(of session: LanguageModelSession, content: String) -> Completion {
        let usage = TokenUsage(
            promptTokens: session.usage.input.totalTokenCount,
            completionTokens: session.usage.output.totalTokenCount)

        let finishReason: FinishReason =
            if let responseTokenLimit, usage.completionTokens >= responseTokenLimit { .length } else { .stop }
        return Completion(content: content, finishReason: finishReason, usage: usage)
    }
}

// MARK: - Request mapping

extension ChatGeneration {
    private static func rejectUnsupportedParameters(of request: ChatCompletionRequest) throws(APIError) {
        if let n = request.n, n != 1 {
            throw APIError.unsupported("Only one choice per request is supported ('n' must be 1).", param: "n")
        }
        if let stop = request.stop, !stop.sequences.isEmpty {
            throw APIError.unsupported("Stop sequences are not supported by the on-device model.", param: "stop")
        }
    }

    private static func options(of request: ChatCompletionRequest) throws(APIError) -> GenerationOptions {
        if let temperature = request.temperature, !(0...2).contains(temperature) {
            throw APIError.invalidRequest("'temperature' must be between 0 and 2.", param: "temperature")
        }
        if let topP = request.topP, !(topP > 0 && topP <= 1) {
            throw APIError.invalidRequest("'top_p' must be greater than 0 and at most 1.", param: "top_p")
        }
        if let limit = request.responseTokenLimit, limit < 1 {
            throw APIError.invalidRequest("The token limit must be at least 1.", param: "max_completion_tokens")
        }

        var samplingMode: GenerationOptions.SamplingMode?
        if request.temperature == 0 {
            // The framework expresses determinism as a sampling mode, not as a zero temperature.
            samplingMode = .greedy
        } else if request.topP != nil || request.seed != nil {
            // A seed only takes effect on an explicit random sampling mode.
            samplingMode = .random(probabilityThreshold: request.topP ?? 1, seed: request.seed)
        }
        return GenerationOptions(
            samplingMode: samplingMode,
            temperature: request.temperature == 0 ? nil : request.temperature,
            maximumResponseTokens: request.responseTokenLimit)
    }
}
