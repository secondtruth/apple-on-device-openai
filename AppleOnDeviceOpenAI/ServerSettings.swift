import Foundation
import OnDeviceServer

/// The server settings the app keeps between launches.
///
/// They live in `UserDefaults`, which also makes each of them a launch argument
/// without further code: macOS reads `-key value` pairs into the defaults, so
///
///     open -a AppleOnDeviceOpenAI --args -port 11600 -autoStart YES
///
/// overrides the stored values for that launch only.
struct ServerSettings: Equatable {
    var host: String
    var port: Int
    var autoStart: Bool
    var logLevel: ServerConfiguration.LogLevel

    static let defaults = ServerSettings(
        host: ServerConfiguration.defaultHost, port: ServerConfiguration.defaultPort,
        autoStart: false, logLevel: .info)

    static let validPorts = 1...65535

    private enum Key {
        static let host = "host"
        static let port = "port"
        static let autoStart = "autoStart"
        static let logLevel = "logLevel"
    }

    static func load(from store: UserDefaults = .standard) -> ServerSettings {
        let port = store.integer(forKey: Key.port)
        return ServerSettings(
            host: store.string(forKey: Key.host) ?? defaults.host,
            port: validPorts.contains(port) ? port : defaults.port,
            autoStart: store.bool(forKey: Key.autoStart),
            logLevel: store.string(forKey: Key.logLevel).flatMap(ServerConfiguration.LogLevel.init(rawValue:)) ?? defaults.logLevel)
    }

    func save(to store: UserDefaults = .standard) {
        store.set(host, forKey: Key.host)
        store.set(port, forKey: Key.port)
        store.set(autoStart, forKey: Key.autoStart)
        store.set(logLevel.rawValue, forKey: Key.logLevel)
    }

    var configuration: ServerConfiguration {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ServerConfiguration(host: host, port: port, logLevel: logLevel, serverVersion: version ?? "dev")
    }
}
