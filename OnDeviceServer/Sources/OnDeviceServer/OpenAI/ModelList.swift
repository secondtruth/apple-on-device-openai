import Vapor

/// The body of `GET /v1/models`.
struct ModelList: Content {
    var object = "list"
    var data: [ModelObject]
}

/// A model in OpenAI's shape, extended with what a client cannot otherwise
/// learn about an on-device model: whether it can be used right now, and why not.
struct ModelObject: Content {
    var id: String
    var object = "model"
    var created: Int
    var ownedBy = "apple"
    var available: Bool
    var unavailableReason: String?
    var contextWindow: Int
    var capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case id, object, created, available, capabilities
        case ownedBy = "owned_by"
        case unavailableReason = "unavailable_reason"
        case contextWindow = "context_window"
    }
}
