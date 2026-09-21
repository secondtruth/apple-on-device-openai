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

    // Each setting is written on its own. Writing them together would also
    // store the values a launch argument supplied, and turn an override meant
    // for one launch into the new default.
    static func persist(host: String, to store: UserDefaults = .standard) {
        store.set(host, forKey: Key.host)
    }

    static func persist(port: Int, to store: UserDefaults = .standard) {
        store.set(port, forKey: Key.port)
    }

    static func persist(autoStart: Bool, to store: UserDefaults = .standard) {
        store.set(autoStart, forKey: Key.autoStart)
    }

    static func removeAll(from store: UserDefaults = .standard) {
        for key in [Key.host, Key.port, Key.autoStart, Key.logLevel] {
            store.removeObject(forKey: key)
        }
    }

    /// The API key is not a member: it lives in the keychain, see `APIKeyStore`.
    func configuration(apiKey: String) -> ServerConfiguration {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return ServerConfiguration(
            host: host, port: port, logLevel: logLevel,
            apiKey: apiKey.isEmpty ? nil : apiKey, serverVersion: version ?? "dev")
    }
}
