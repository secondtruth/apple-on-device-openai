import Vapor

/// The body of `GET /status`: the state of the default model, for people and
/// monitoring. `GET /v1/models` carries the same facts per model.
struct ServerStatus: Content {
    var modelAvailable: Bool
    var reason: String
    var unavailableReason: String?
    var supportedLanguages: [String]
    var contextWindow: Int
    var serverVersion: String

    enum CodingKeys: String, CodingKey {
        case reason
        case modelAvailable = "model_available"
        case unavailableReason = "unavailable_reason"
        case supportedLanguages = "supported_languages"
        case contextWindow = "context_window"
        case serverVersion = "server_version"
    }

    init(serverVersion: String) {
        let model = OnDeviceModel.general
        let availability = model.availability
        modelAvailable = availability.isAvailable
        reason = availability.explanation ?? "The on-device model is available."
        unavailableReason = availability.isAvailable ? nil : availability.status.rawValue
        // Minimal BCP 47 tags ("de", "en-GB") are what clients compare against.
        supportedLanguages = model.languageModel.supportedLanguages.map(\.minimalIdentifier).sorted()
        contextWindow = model.languageModel.contextSize
        self.serverVersion = serverVersion
    }
}
