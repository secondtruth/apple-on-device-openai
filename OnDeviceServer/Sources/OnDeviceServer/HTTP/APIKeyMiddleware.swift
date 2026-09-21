import Vapor

/// Requires the configured key as a bearer token, the way OpenAI clients send theirs.
struct APIKeyMiddleware: AsyncMiddleware {
    let expectedKey: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            throw APIError.invalidAPIKey(missing: true)
        }
        guard matches(token) else {
            throw APIError.invalidAPIKey(missing: false)
        }
        return try await next.respond(to: request)
    }

    // Compares every byte regardless of where the first difference is, so the
    // response time does not reveal how much of a guessed key was right.
    private func matches(_ candidate: String) -> Bool {
        let expected = Array(expectedKey.utf8)
        let given = Array(candidate.utf8)
        var difference: UInt8 = expected.count == given.count ? 0 : 1
        for index in expected.indices {
            difference |= expected[index] ^ (index < given.count ? given[index] : 0)
        }
        return difference == 0
    }
}
