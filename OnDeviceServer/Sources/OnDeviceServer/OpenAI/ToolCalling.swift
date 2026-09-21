import Foundation

/// An entry of the request's `tools` array. Only `function` tools exist in the
/// Chat Completions API.
struct ToolDefinition: Codable, Sendable {
    var type: String
    var function: Function

    struct Function: Codable, Sendable {
        var name: String
        var description: String?
        var parameters: JSONValue?
    }
}

/// `tool_choice`: one of the mode strings, or an object naming a function.
enum ToolChoice: Codable, Sendable, Equatable {
    case none
    case auto
    case required
    case function(name: String)

    init(from decoder: Decoder) throws {
        if let mode = try? decoder.singleValueContainer().decode(String.self) {
            switch mode {
            case "none": self = .none
            case "auto": self = .auto
            case "required": self = .required
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "tool_choice must be \"none\", \"auto\", \"required\" or a function object"))
            }
            return
        }
        let named = try NamedFunction(from: decoder)
        self = .function(name: named.function.name)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .none: try "none".encode(to: encoder)
        case .auto: try "auto".encode(to: encoder)
        case .required: try "required".encode(to: encoder)
        case .function(let name):
            try NamedFunction(type: "function", function: .init(name: name)).encode(to: encoder)
        }
    }

    private struct NamedFunction: Codable {
        var type: String
        var function: Name

        struct Name: Codable {
            var name: String
        }
    }
}

/// A tool call, as the model emits it in a response and as the client echoes it
/// back in the assistant message of the follow-up request.
struct ToolCall: Codable, Sendable, Equatable {
    var id: String
    var type: String = "function"
    var function: Function

    struct Function: Codable, Sendable, Equatable {
        var name: String
        /// A JSON document, serialized: the API transports arguments as a string.
        var arguments: String
    }
}
