import Vapor

/// Turns every error into OpenAI's error envelope.
///
/// It replaces Vapor's `ErrorMiddleware`, whose `{"error": true, "reason": …}`
/// body no OpenAI client can read.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            let apiError = APIError(describing: error)
            let level: Logger.Level = apiError.status.code >= 500 ? .error : .notice
            request.logger.log(level: level, "request failed", metadata: [
                "status": "\(apiError.status.code)",
                "code": "\(apiError.code ?? "-")",
                "error": "\(apiError.message)",
            ])
            return try apiError.response()
        }
    }
}

extension APIError {
    func response() throws -> Response {
        let response = Response(status: status)
        try response.content.encode(envelope, as: .json)
        if status == .unauthorized {
            response.headers.replaceOrAdd(name: .wwwAuthenticate, value: "Bearer")
        }
        if let retryAfter {
            let seconds = max(1, Int(retryAfter.timeIntervalSinceNow.rounded(.up)))
            response.headers.replaceOrAdd(name: .retryAfter, value: String(seconds))
        }
        return response
    }

    /// Classifies an arbitrary error. Generation errors are mapped where they
    /// are thrown; what arrives here otherwise is a routing or decoding failure.
    init(describing error: Error) {
        switch error {
        case let apiError as APIError:
            self = apiError
        case let decodingError as DecodingError:
            self = .invalidRequest(decodingError.requestDescription, param: decodingError.param)
        case let abort as AbortError where abort.status == .notFound:
            self = APIError(
                status: .notFound, kind: .notFound,
                message: "Unknown endpoint. This server implements /v1/models and /v1/chat/completions.",
                code: "unknown_url")
        case let abort as AbortError:
            let kind: Kind = abort.status.code >= 500 ? .api : .invalidRequest
            self = APIError(status: abort.status, kind: kind, message: abort.reason)
        default:
            self = .internalError(String(describing: error))
        }
    }
}

extension DecodingError {
    /// The offending JSON path in OpenAI's `param` notation, e.g. `messages[0].role`.
    fileprivate var param: String? {
        let path: [CodingKey]
        switch self {
        case .keyNotFound(let key, let context): path = context.codingPath + [key]
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        @unknown default: return nil
        }
        let joined = path.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return joined.isEmpty ? nil : joined
    }

    fileprivate var requestDescription: String {
        switch self {
        case .keyNotFound(let key, _):
            return "Missing required parameter: '\(key.stringValue)'."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "Invalid type for '\(param ?? "request body")': \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Invalid request body: \(context.debugDescription)"
        @unknown default:
            return "Invalid request body."
        }
    }
}
