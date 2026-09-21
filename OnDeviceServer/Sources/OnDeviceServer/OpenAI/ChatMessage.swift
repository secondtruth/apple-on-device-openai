import Foundation

/// One entry of the request's `messages` array.
struct ChatMessage: Codable, Sendable {
    enum Role: String, Codable, Sendable {
        case system, developer, user, assistant
    }

    var role: Role
    var content: MessageContent?
}

/// Message content is a plain string or an array of typed parts.
enum MessageContent: Codable, Sendable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self = .text(text)
        } else {
            self = .parts(try decoder.singleValueContainer().decode([ContentPart].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text): try text.encode(to: encoder)
        case .parts(let parts): try parts.encode(to: encoder)
        }
    }
}

struct ContentPart: Codable, Sendable {
    var type: String
    var text: String?
}
