import Foundation
import FoundationModels

/// One chat completion, from a validated request to the model's output.
///
/// Streaming and non-streaming responses consume the same event sequence, so
/// both paths share validation, option mapping, tool handling and error mapping.
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
        var toolCalls: [ToolCall]
        var finishReason: FinishReason
        var usage: TokenUsage
    }

    let model: OnDeviceModel
    private let conversation: Conversation
    private let tools: [ClientExecutedTool]
    private let options: GenerationOptions
    private let responseTokenLimit: Int?
    private let allowsParallelToolCalls: Bool

    /// Validates the whole request, so that everything a client got wrong is
    /// reported before the model is involved.
    init(_ request: ChatCompletionRequest) throws(APIError) {
        try Self.rejectUnsupportedParameters(of: request)
        model = try OnDeviceModel.named(request.model)

        let offered = try Self.tools(of: request)
        let (enabled, callingMode) = try Self.toolSelection(request.toolChoice, from: offered)
        tools = enabled
        conversation = try Conversation(messages: request.messages, tools: enabled)
        options = try Self.options(of: request, toolCallingMode: callingMode)
        responseTokenLimit = request.responseTokenLimit
        allowsParallelToolCalls = request.parallelToolCalls ?? true
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
        let session = LanguageModelSession(
            model: model.languageModel, tools: tools, transcript: conversation.transcript)
        // The default policy reverts the transcript when a turn fails, which would
        // erase the tool calls that `ClientExecutedTool` fails the turn to hand over.
        session.transcriptErrorHandlingPolicy = .preserveTranscript

        var content = ""
        do {
            for try await snapshot in textStream(from: session) {
                if snapshot.content.hasPrefix(content) {
                    continuation.yield(.textDelta(String(snapshot.content.dropFirst(content.count))))
                }
                content = snapshot.content
            }
        } catch let error as LanguageModelSession.ToolCallError where error.underlyingError is ClientExecutedTool.Handoff {
            continuation.yield(.completed(completion(of: session, content: content, toolCalls: requestedToolCalls(in: session))))
            return
        }
        continuation.yield(.completed(completion(of: session, content: content, toolCalls: [])))
    }

    // A request that ends in tool results asks nothing new, but the framework
    // only generates in answer to a prompt. An empty prompt adds a turn without
    // segments, and the model answers from the tool output before it.
    private func textStream(from session: LanguageModelSession) -> LanguageModelSession.ResponseStream<String> {
        if let prompt = conversation.prompt {
            session.streamResponse(to: Prompt(prompt), options: options)
        } else {
            session.streamResponse(options: options) {}
        }
    }

    private func requestedToolCalls(in session: LanguageModelSession) -> [ToolCall] {
        let newEntries = session.transcript.dropFirst(conversation.transcript.count)
        let calls = newEntries.reversed().lazy.compactMap { entry -> Transcript.ToolCalls? in
            guard case .toolCalls(let calls) = entry else { return nil }
            return calls
        }.first ?? Transcript.ToolCalls([])

        let toolCalls = calls.map { call in
            ToolCall(
                id: "call_" + call.id.replacingOccurrences(of: "-", with: "").lowercased(),
                function: .init(name: call.toolName, arguments: call.arguments.jsonString))
        }
        // The model cannot be told to call one tool at a time. Returning only the
        // first call is equivalent: it decides on the rest when it sees that result.
        return allowsParallelToolCalls ? toolCalls : Array(toolCalls.prefix(1))
    }

    private func completion(of session: LanguageModelSession, content: String, toolCalls: [ToolCall]) -> Completion {
        let usage = TokenUsage(
            promptTokens: session.usage.input.totalTokenCount,
            completionTokens: session.usage.output.totalTokenCount)

        let finishReason: FinishReason =
            if !toolCalls.isEmpty {
                .toolCalls
            } else if let responseTokenLimit, usage.completionTokens >= responseTokenLimit {
                .length
            } else {
                .stop
            }
        return Completion(content: content, toolCalls: toolCalls, finishReason: finishReason, usage: usage)
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

    private static func tools(of request: ChatCompletionRequest) throws(APIError) -> [ClientExecutedTool] {
        var tools: [ClientExecutedTool] = []
        for (index, definition) in (request.tools ?? []).enumerated() {
            let tool = try ClientExecutedTool(definition, index: index)
            guard !tools.contains(where: { $0.name == tool.name }) else {
                throw APIError.invalidRequest(
                    "Duplicate tool name '\(tool.name)'.", param: "tools[\(index)].function.name")
            }
            tools.append(tool)
        }
        return tools
    }

    /// Maps `tool_choice` onto the framework's calling mode. It has no notion of
    /// forcing one particular tool, so a named choice enables only that tool
    /// and requires a call.
    private static func toolSelection(
        _ choice: ToolChoice?, from offered: [ClientExecutedTool]
    ) throws(APIError) -> (enabled: [ClientExecutedTool], mode: GenerationOptions.ToolCallingMode?) {
        switch choice {
        case nil, .auto:
            return (offered, nil)
        case .some(.none):
            return (offered, offered.isEmpty ? nil : .disallowed)
        case .required:
            guard !offered.isEmpty else {
                throw APIError.invalidRequest("'tool_choice' is 'required' but no tools were given.", param: "tool_choice")
            }
            return (offered, .required)
        case .function(let name):
            guard let tool = offered.first(where: { $0.name == name }) else {
                throw APIError.invalidRequest("'tool_choice' names '\(name)', which is not in 'tools'.", param: "tool_choice")
            }
            return ([tool], .required)
        }
    }

    private static func options(
        of request: ChatCompletionRequest, toolCallingMode: GenerationOptions.ToolCallingMode?
    ) throws(APIError) -> GenerationOptions {
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
            maximumResponseTokens: request.responseTokenLimit,
            toolCallingMode: toolCallingMode)
    }
}
