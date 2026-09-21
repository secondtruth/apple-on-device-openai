import Foundation
import Logging

/// What the host application decides about the server.
public struct ServerConfiguration: Sendable, Equatable {
    /// Mirrors swift-log's levels, so the host app configures logging without
    /// depending on swift-log itself.
    public enum LogLevel: String, Sendable, CaseIterable {
        case trace, debug, info, notice, warning, error, critical

        var loggerLevel: Logger.Level {
            Logger.Level(rawValue: rawValue) ?? .info
        }
    }

    public static let defaultHost = "127.0.0.1"
    public static let defaultPort = 11535

    public var host: String
    public var port: Int
    public var logLevel: LogLevel
    /// When set, every endpoint but `/health` requires `Authorization: Bearer <key>`.
    public var apiKey: String?
    /// Reported by `GET /status`; the package cannot see the app bundle's version.
    public var serverVersion: String

    public init(
        host: String = defaultHost, port: Int = defaultPort,
        logLevel: LogLevel = .info, apiKey: String? = nil, serverVersion: String = "dev"
    ) {
        self.host = host
        self.port = port
        self.logLevel = logLevel
        self.apiKey = apiKey
        self.serverVersion = serverVersion
    }

    /// The URL clients configure as their OpenAI base URL.
    public func baseURL(advertisedHost: String? = nil) -> String {
        "http://\(advertisedHost ?? host):\(port)/v1"
    }
}
