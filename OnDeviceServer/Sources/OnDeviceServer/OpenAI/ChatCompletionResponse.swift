import Vapor

/// The body of a non-streaming chat completion.
struct ChatCompletionResponse: Content {
    var id: String
    var object = "chat.completion"
    var created: Int
    var model: String
    var choices: [Choice]
    var usage: TokenUsage

    struct Choice: Codable, Sendable {
        var index = 0
        var message: AssistantMessage
        var finishReason: FinishReason

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
}

struct AssistantMessage: Codable, Sendable {
    var role = "assistant"
    var content: String
}

enum FinishReason: String, Codable, Sendable {
    case stop
    case length
}

struct TokenUsage: Codable, Sendable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int { promptTokens + completionTokens }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(promptTokens, forKey: .promptTokens)
        try container.encode(completionTokens, forKey: .completionTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
    }
}
