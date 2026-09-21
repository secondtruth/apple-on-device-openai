import Logging
import os

/// Forwards swift-log records to the macOS unified log.
struct UnifiedLogHandler: LogHandler {
    static let subsystem = "apple-on-device-openai"

    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info
    private let log: os.Logger

    init(label: String) {
        log = os.Logger(subsystem: Self.subsystem, category: label)
    }

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let merged = metadata.merging(event.metadata ?? [:]) { $1 }
        let fields = merged.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let text = fields.isEmpty ? "\(event.message)" : "\(event.message) \(fields)"
        // Prompts and model output never reach a log line, so nothing here is private.
        log.log(level: event.level.unifiedLogType, "\(text, privacy: .public)")
    }
}

extension Logging.Logger.Level {
    fileprivate var unifiedLogType: OSLogType {
        switch self {
        case .trace, .debug: .debug
        case .info: .info
        case .notice, .warning: .default
        case .error: .error
        case .critical: .fault
        }
    }
}
