import Vapor

/// An error a client sees, in the shape OpenAI clients already unwrap:
/// `{"error": {"message", "type", "param", "code"}}` plus the HTTP status.
struct APIError: Error, Sendable, Equatable {
    /// OpenAI's error families. Clients branch on these, so no new ones are invented.
    enum Kind: String, Sendable {
        case invalidRequest = "invalid_request_error"
        case notFound = "not_found_error"
        case rateLimit = "rate_limit_error"
        case api = "api_error"
    }

    var status: HTTPResponseStatus
    var kind: Kind
    var message: String
    var param: String?
    var code: String?
    var retryAfter: Date?

    static func invalidRequest(_ message: String, param: String? = nil, code: String? = nil) -> APIError {
        APIError(status: .badRequest, kind: .invalidRequest, message: message, param: param, code: code)
    }

    static func unsupported(_ message: String, param: String) -> APIError {
        .invalidRequest(message, param: param, code: "unsupported_parameter")
    }

    static func modelNotFound(_ id: String, known: [String]) -> APIError {
        APIError(
            status: .notFound, kind: .notFound,
            message: "The model '\(id)' does not exist. Available models: \(known.joined(separator: ", ")).",
            param: "model", code: "model_not_found")
    }

    static func internalError(_ message: String) -> APIError {
        APIError(status: .internalServerError, kind: .api, message: message, code: "internal_error")
    }
}

extension APIError {
    /// The JSON body for this error.
    var envelope: Envelope {
        Envelope(error: .init(message: message, type: kind.rawValue, param: param, code: code))
    }

    struct Envelope: Content {
        var error: Body

        struct Body: Codable, Sendable {
            var message: String
            var type: String
            var param: String?
            var code: String?

            // `param` and `code` are null rather than absent, as in OpenAI's responses.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(message, forKey: .message)
                try container.encode(type, forKey: .type)
                try container.encode(param, forKey: .param)
                try container.encode(code, forKey: .code)
            }
        }
    }
}
