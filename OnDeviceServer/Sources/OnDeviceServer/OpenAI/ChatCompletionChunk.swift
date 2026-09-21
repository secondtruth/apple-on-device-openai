import Foundation

/// One `data:` event of a streaming chat completion.
struct ChatCompletionChunk: Codable, Sendable {
    var id: String
    var object = "chat.completion.chunk"
    var created: Int
    var model: String
    var choices: [Choice]
    /// Present only on the trailing chunk a client asked for with
    /// `stream_options.include_usage`; that chunk has no choices.
    var usage: TokenUsage?

    struct Choice: Codable, Sendable {
        var index = 0
        var delta: Delta
        var finishReason: FinishReason?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }

        // `finish_reason` is null on every chunk but the last; clients read the
        // key unconditionally, so it is never omitted.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(index, forKey: .index)
            try container.encode(delta, forKey: .delta)
            try container.encode(finishReason, forKey: .finishReason)
        }
    }

    struct Delta: Codable, Sendable {
        var role: String?
        var content: String?
    }
}
