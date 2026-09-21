import Foundation
import FoundationModels

/// A model this server exposes under an OpenAI model id.
public struct OnDeviceModel: Sendable {
    public let id: String
    let languageModel: SystemLanguageModel

    /// The general-purpose system model; used when a request names no model.
    public static let general = OnDeviceModel(id: "apple-on-device", languageModel: .default)

    /// The system model adapted for tagging and extraction.
    public static let contentTagging = OnDeviceModel(
        id: "apple-on-device-content-tagging",
        languageModel: SystemLanguageModel(useCase: .contentTagging))

    public static let catalog = [general, contentTagging]

    public var availability: ModelAvailability {
        ModelAvailability(languageModel.availability)
    }

    static func named(_ id: String?) throws(APIError) -> OnDeviceModel {
        guard let id else { return general }
        guard let model = catalog.first(where: { $0.id == id }) else {
            throw APIError.modelNotFound(id, known: catalog.map(\.id))
        }
        return model
    }
}

extension OnDeviceModel {
    // Foundation Models shipped with macOS 26 on 2025-09-15. The field is
    // mandatory in OpenAI's model object; a fixed date beats a fresh timestamp
    // on every call, which clients would read as a new model.
    private static let created = 1_757_894_400

    var modelObject: ModelObject {
        let availability = availability
        return ModelObject(
            id: id,
            created: Self.created,
            available: availability.isAvailable,
            unavailableReason: availability.isAvailable ? nil : availability.status.rawValue,
            contextWindow: languageModel.contextSize,
            capabilities: capabilityNames)
    }

    private var capabilityNames: [String] {
        let known: [(LanguageModelCapabilities.Capability, String)] = [
            (.toolCalling, "tool_calling"),
            (.guidedGeneration, "structured_output"),
            (.reasoning, "reasoning"),
            (.vision, "vision"),
        ]
        return known.filter { languageModel.capabilities.contains($0.0) }.map(\.1)
    }
}
