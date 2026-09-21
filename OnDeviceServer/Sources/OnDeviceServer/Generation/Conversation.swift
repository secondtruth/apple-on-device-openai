import Foundation
import FoundationModels

/// An OpenAI message list, restated as what a `LanguageModelSession` needs: the
/// history as a transcript, and the turn still to be answered.
struct Conversation: Sendable {
    /// Everything before the turn to answer.
    let transcript: Transcript
    /// The user's latest message.
    let prompt: String

    init(messages: [ChatMessage]) throws(APIError) {
        guard let last = messages.last else {
            throw APIError.invalidRequest("'messages' must contain at least one message.", param: "messages")
        }
        guard last.role == .user else {
            throw APIError.invalidRequest(
                "The last message must have the role 'user'; the on-device model cannot continue a "
                    + "prefilled assistant message.",
                param: "messages[\(messages.count - 1)].role")
        }

        var entries: [Transcript.Entry] = []
        var instructionTexts: [String] = []

        for (index, message) in messages.dropLast().enumerated() {
            let text = try Self.text(of: message, path: "messages[\(index)]")
            switch message.role {
            case .system, .developer:
                instructionTexts.append(text)
            case .user:
                entries.append(.prompt(.init(segments: [Self.segment(text)])))
            case .assistant:
                entries.append(.response(.init(assetIDs: [], segments: [Self.segment(text)])))
            }
        }

        // A session reads its instructions from the first entry only, so system
        // messages from anywhere in the list are gathered there.
        if !instructionTexts.isEmpty {
            let segments = [Self.segment(instructionTexts.joined(separator: "\n\n"))]
            entries.insert(.instructions(.init(segments: segments, toolDefinitions: [])), at: 0)
        }

        self.transcript = Transcript(entries: entries)
        self.prompt = try Self.text(of: last, path: "messages[\(messages.count - 1)]")
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
}
