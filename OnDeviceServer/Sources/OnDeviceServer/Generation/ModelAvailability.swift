import Foundation
import FoundationModels

/// Whether an on-device model can generate right now, and if not, why — in
/// words that tell the person at the Mac what to do about it.
public struct ModelAvailability: Sendable, Equatable {
    public enum Status: String, Sendable {
        case available
        case deviceNotEligible = "device_not_eligible"
        case appleIntelligenceDisabled = "apple_intelligence_disabled"
        case modelDownloading = "model_downloading"
        case unknown = "model_unavailable"
    }

    public let status: Status

    public var isAvailable: Bool { status == .available }

    /// Nil when the model is available.
    public var explanation: String? {
        switch status {
        case .available:
            nil
        case .deviceNotEligible:
            "This Mac cannot run Apple Intelligence. It requires a Mac with Apple silicon."
        case .appleIntelligenceDisabled:
            "Apple Intelligence is turned off. Turn it on in System Settings › Apple Intelligence & Siri, then retry."
        case .modelDownloading:
            "The on-device model is still downloading. macOS fetches it in the background while the Mac is "
                + "online and on power; retry in a few minutes."
        case .unknown:
            "The on-device model is unavailable for a reason this version of the server does not know."
        }
    }

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available: status = .available
        case .unavailable(.deviceNotEligible): status = .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): status = .appleIntelligenceDisabled
        case .unavailable(.modelNotReady): status = .modelDownloading
        case .unavailable: status = .unknown
        @unknown default: status = .unknown
        }
    }
}

extension APIError {
    /// 503 rather than 4xx: the request is fine, the machine is not ready.
    static func modelUnavailable(_ availability: ModelAvailability) -> APIError {
        APIError(
            status: .serviceUnavailable, kind: .api,
            message: availability.explanation ?? "The on-device model is unavailable.",
            code: availability.status.rawValue,
            // Only a download resolves by waiting; the other states need the user.
            retryAfter: availability.status == .modelDownloading ? Date(timeIntervalSinceNow: 60) : nil)
    }
}
