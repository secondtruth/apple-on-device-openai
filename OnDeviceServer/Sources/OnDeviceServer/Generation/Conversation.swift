import Foundation
import FoundationModels

/// An OpenAI message list, restated as what a `LanguageModelSession` needs: the
/// history as a transcript, and the turn still to be answered.
struct Conversation: Sendable {
    /// Everything before the turn to answer.
    let transcript: Transcript
    /// The user's latest message. Nil when the request ends in tool results: the
    /// model then continues the turn it started, and nothing new is asked.
    let prompt: String?

    init(messages: [ChatMessage], tools: [ClientExecutedTool]) throws(APIError) {
        guard let last = messages.last else {
            throw APIError.invalidRequest("'messages' must contain at least one message.", param: "messages")
        }

        var entries: [Transcript.Entry] = []
        var instructionTexts: [String] = []
        var toolNamesByCallID: [String: String] = [:]
        var prompt: String?

        for (index, message) in messages.enumerated() {
            let path = "messages[\(index)]"
            let text = try Self.text(of: message, path: path)
            switch message.role {
            case .system, .developer:
                instructionTexts.append(text)

            case .user:
                if index == messages.count - 1 {
                    prompt = text
                } else {
                    entries.append(.prompt(.init(segments: [Self.segment(text)])))
                }

            case .assistant:
                if !text.isEmpty {
                    entries.append(.response(.init(assetIDs: [], segments: [Self.segment(text)])))
                }
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    var calls: [Transcript.ToolCall] = []
                    for (callIndex, call) in toolCalls.enumerated() {
                        toolNamesByCallID[call.id] = call.function.name
                        calls.append(try Self.transcriptCall(call, path: "\(path).tool_calls[\(callIndex)]"))
                    }
                    entries.append(.toolCalls(.init(calls)))
                }

            case .tool:
                guard let callID = message.toolCallID else {
                    throw APIError.invalidRequest(
                        "Tool messages need a 'tool_call_id'.", param: "\(path).tool_call_id")
                }
                guard let toolName = toolNamesByCallID[callID] else {
                    throw APIError.invalidRequest(
                        "'\(callID)' does not match a tool call of an earlier assistant message.",
                        param: "\(path).tool_call_id")
                }
                entries.append(.toolOutput(.init(id: callID, toolName: toolName, segments: [Self.segment(text)])))
            }
        }

        guard last.role == .user || last.role == .tool else {
            throw APIError.invalidRequest(
                "The last message must have the role 'user' or 'tool'; the on-device model cannot "
                    + "continue a prefilled assistant message.",
                param: "messages[\(messages.count - 1)].role")
        }

        // A session reads its instructions from the first entry only, so system
        // messages from anywhere in the list are gathered there. Tool definitions
        // live in the same entry; without it the model would not see them.
        if !instructionTexts.isEmpty || !tools.isEmpty {
            let segments = instructionTexts.isEmpty ? [] : [Self.segment(instructionTexts.joined(separator: "\n\n"))]
            let definitions = tools.map { Transcript.ToolDefinition(tool: $0) }
            entries.insert(.instructions(.init(segments: segments, toolDefinitions: definitions)), at: 0)
        }

        self.transcript = Transcript(entries: entries)
        self.prompt = prompt
    }

    private static func segment(_ text: String) -> Transcript.Segment {
        .text(.init(content: text))
    }

    private static func text(of message: ChatMessage, path: String) throws(APIError) -> String {
        switch message.content {
        case nil:
            return ""
        case .text(let text):
            return text
        case .parts(let parts):
            var texts: [String] = []
            for (index, part) in parts.enumerated() {
                guard part.type == "text", let text = part.text else {
                    throw APIError.invalidRequest(
                        "Content parts of type '\(part.type)' are not supported; this server accepts text only.",
                        param: "\(path).content[\(index)]", code: "unsupported_content_type")
                }
                texts.append(text)
            }
            return texts.joined(separator: "\n")
        }
    }

    private static func transcriptCall(_ call: ToolCall, path: String) throws(APIError) -> Transcript.ToolCall {
        // Some clients send an empty string for a call without arguments.
        let json = call.function.arguments.isEmpty ? "{}" : call.function.arguments
        do {
            return Transcript.ToolCall(
                id: call.id, toolName: call.function.name, arguments: try GeneratedContent(json: json))
        } catch {
            throw APIError.invalidRequest(
                "Tool call arguments must be a JSON document.", param: "\(path).function.arguments")
        }
    }
}
