import Testing
import Vapor
import VaporTesting

@testable import OnDeviceServer

@Suite struct APIKeyTests {
    private func withServer(
        apiKey: String?, _ test: (Application) async throws -> Void
    ) async throws {
        try await withApp(configure: { app in
            OnDeviceServer.configure(app, with: ServerConfiguration(apiKey: apiKey))
        }, test)
    }

    @Test func withoutAKeyEveryEndpointIsOpen() async throws {
        try await withServer(apiKey: nil) { app in
            try await app.testing().test(.GET, "v1/models") { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func anEmptyKeyMeansNoKey() async throws {
        try await withServer(apiKey: "") { app in
            try await app.testing().test(.GET, "v1/models") { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func aMissingKeyIsRejectedInOpenAIsEnvelope() async throws {
        try await withServer(apiKey: "secret") { app in
            try await app.testing().test(.GET, "v1/models") { response in
                #expect(response.status == .unauthorized)
                #expect(response.headers.first(name: .wwwAuthenticate) == "Bearer")
                let envelope = try response.content.decode(APIError.Envelope.self)
                #expect(envelope.error.type == "invalid_request_error")
                #expect(envelope.error.code == nil)
            }
        }
    }

    @Test(arguments: ["wrong", "secre", "secrets", "Secret", ""])
    func aWrongKeyIsRejected(candidate: String) async throws {
        try await withServer(apiKey: "secret") { app in
            try await app.testing().test(.GET, "status", headers: ["Authorization": "Bearer \(candidate)"]) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test func theRightKeyIsAccepted() async throws {
        try await withServer(apiKey: "secret") { app in
            try await app.testing().test(.GET, "v1/models", headers: ["Authorization": "Bearer secret"]) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func healthStaysOpenForProbes() async throws {
        try await withServer(apiKey: "secret") { app in
            try await app.testing().test(.GET, "health") { response in
                #expect(response.status == .ok)
            }
        }
    }
}
