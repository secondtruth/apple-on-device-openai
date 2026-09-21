import Vapor

/// The body of `POST /v1/chat/completions`.
///
/// Sampling penalties, `logit_bias` and `user` are accepted and ignored: the
/// on-device model has no equivalent and they do not change what a client may
/// rely on. Parameters that would change the shape of the result (`n`, `stop`)
/// are decoded so they can be rejected instead of silently dropped.
struct ChatCompletionRequest: Content {
    var model: String?
    var messages: [ChatMessage]
    var maxTokens: Int?
    var maxCompletionTokens: Int?
    var temperature: Double?
    var topP: Double?
    var seed: UInt64?
    var n: Int?
    var stop: StopSequences?
    var stream: Bool?
    var streamOptions: StreamOptions?
    var tools: [ToolDefinition]?
    var toolChoice: ToolChoice?
    var parallelToolCalls: Bool?
    var responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, seed, n, stop, stream, tools
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case topP = "top_p"
        case streamOptions = "stream_options"
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case responseFormat = "response_format"
    }

    /// `max_completion_tokens` superseded `max_tokens`; clients send either.
    var responseTokenLimit: Int? { maxCompletionTokens ?? maxTokens }
}

struct StreamOptions: Codable, Sendable {
    var includeUsage: Bool?

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

/// `stop` is a single string or an array of strings.
struct StopSequences: Codable, Sendable {
    var sequences: [String]

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            sequences = [single]
        } else {
            sequences = try decoder.singleValueContainer().decode([String].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        try sequences.encode(to: encoder)
    }
}

struct ResponseFormat: Codable, Sendable {
    var type: String
    var jsonSchema: JSONSchemaFormat?

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    struct JSONSchemaFormat: Codable, Sendable {
        var name: String
        var description: String?
        var schema: JSONValue?
    }
}
