import Vapor

/// `POST /v1/chat/completions`
struct ChatCompletionsHandler: Sendable {
    func handle(_ request: Request) async throws -> Response {
        let body = try request.content.decode(ChatCompletionRequest.self)
        let generation = try ChatGeneration(body)

        let availability = generation.model.availability
        guard availability.isAvailable else {
            throw APIError.modelUnavailable(availability)
        }

        let context = CompletionContext(
            id: "chatcmpl-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            created: Int(Date().timeIntervalSince1970),
            model: generation.model.id,
            logger: request.logger,
            started: .now)

        request.logger.info("completion started", metadata: [
            "completion": "\(context.id)", "model": "\(context.model)",
            "stream": "\(body.stream ?? false)", "messages": "\(body.messages.count)",
            "tools": "\(body.tools?.count ?? 0)",
        ])

        return body.stream == true
            ? try await streamed(generation, context, includeUsage: body.streamOptions?.includeUsage ?? false)
            : try await collected(generation, context)
    }

    // MARK: Non-streaming

    // Vapor does not tell a handler when its client disconnects, so a
    // non-streaming generation runs to the end even if nobody is listening.
    private func collected(_ generation: ChatGeneration, _ context: CompletionContext) async throws -> Response {
        var completion: ChatGeneration.Completion?
        for try await event in generation.events() {
            if case .completed(let result) = event { completion = result }
        }
        guard let completion else {
            throw APIError.internalError("The generation ended without a result.")
        }
        context.logFinished(completion)

        let message = AssistantMessage(
            content: completion.content.isEmpty && !completion.toolCalls.isEmpty ? nil : completion.content,
            toolCalls: completion.toolCalls.isEmpty ? nil : completion.toolCalls)
        let body = ChatCompletionResponse(
            id: context.id, created: context.created, model: context.model,
            choices: [.init(message: message, finishReason: completion.finishReason)],
            usage: completion.usage)

        let response = Response(status: .ok)
        try response.content.encode(body, as: .json)
        return response
    }

    // MARK: Streaming

    private func streamed(
        _ generation: ChatGeneration, _ context: CompletionContext, includeUsage: Bool
    ) async throws -> Response {
        let events = generation.events()

        // Once the status line is sent, a failure can only be reported inside the
        // stream. Most failures — context overflow, guardrails, rate limits — hit
        // before the first token, so the first event is awaited here, where they
        // still become a proper HTTP error.
        var iterator = events.makeAsyncIterator()
        let first = try await iterator.next()

        return Response(status: .ok, headers: ServerSentEventWriter.headers, body: .init(managedAsyncStream: { body in
            let writer = ServerSentEventWriter(body: body)
            do {
                try await writer.send(context.chunk(.init(role: "assistant", content: "")))
                if let first {
                    try await forward(first, to: writer, context, includeUsage: includeUsage)
                }
                for try await event in events {
                    try await forward(event, to: writer, context, includeUsage: includeUsage)
                }
                try await writer.sendDone()
            } catch let error as APIError {
                context.logger.error("completion failed mid-stream", metadata: [
                    "completion": "\(context.id)", "error": "\(error.message)",
                ])
                try? await writer.send(error.envelope)
            } catch {
                // A failed write: the client is gone. Leaving this scope drops the
                // event stream, which cancels the generation.
                context.logger.info("client disconnected, generation cancelled", metadata: [
                    "completion": "\(context.id)", "duration_ms": "\(context.elapsedMilliseconds)",
                ])
            }
        }))
    }

    private func forward(
        _ event: ChatGeneration.Event, to writer: ServerSentEventWriter,
        _ context: CompletionContext, includeUsage: Bool
    ) async throws {
        switch event {
        case .textDelta(let text):
            guard !text.isEmpty else { return }
            try await writer.send(context.chunk(.init(content: text)))

        case .completed(let completion):
            if !completion.toolCalls.isEmpty {
                let deltas = completion.toolCalls.enumerated().map { index, call in
                    ChatCompletionChunk.ToolCallDelta(index: index, id: call.id, function: call.function)
                }
                try await writer.send(context.chunk(.init(toolCalls: deltas)))
            }
            try await writer.send(context.chunk(.init(), finishReason: completion.finishReason))
            if includeUsage {
                try await writer.send(ChatCompletionChunk(
                    id: context.id, created: context.created, model: context.model,
                    choices: [], usage: completion.usage))
            }
            context.logFinished(completion)
        }
    }
}

/// What every chunk and log line of one completion has in common.
private struct CompletionContext: Sendable {
    let id: String
    let created: Int
    let model: String
    let logger: Logger
    let started: ContinuousClock.Instant

    var elapsedMilliseconds: Int64 {
        let elapsed = ContinuousClock.now - started
        return elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
    }

    func chunk(_ delta: ChatCompletionChunk.Delta, finishReason: FinishReason? = nil) -> ChatCompletionChunk {
        ChatCompletionChunk(
            id: id, created: created, model: model,
            choices: [.init(delta: delta, finishReason: finishReason)])
    }

    func logFinished(_ completion: ChatGeneration.Completion) {
        logger.info("completion finished", metadata: [
            "completion": "\(id)", "finish_reason": "\(completion.finishReason.rawValue)",
            "tool_calls": "\(completion.toolCalls.count)",
            "prompt_tokens": "\(completion.usage.promptTokens)",
            "completion_tokens": "\(completion.usage.completionTokens)",
            "duration_ms": "\(elapsedMilliseconds)",
        ])
    }
}
