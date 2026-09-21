import AppKit
import Observation
import OnDeviceServer

/// The state behind the server window: settings, lifecycle and model availability.
@MainActor
@Observable
final class ServerViewModel {
    private(set) var isRunning = false
    private(set) var isTransitioning = false
    private(set) var lastError: String?
    private(set) var availability = OnDeviceModel.general.availability
    private(set) var bindableAddresses = NetworkInterfaces.bindableAddresses()
    /// The configuration of the running server; the settings may have moved on since.
    private(set) var activeConfiguration: ServerConfiguration?

    var host: String { didSet { persist() } }
    var portText: String { didSet { persist() } }
    var autoStart: Bool { didSet { persist() } }
    /// Empty means the server accepts any client. Persisted by `persistAPIKey()`,
    /// not on every keystroke: each write is a keychain transaction.
    var apiKey = ""
    /// True until the keychain has answered. The server must not start before
    /// that: it would run without the key it is supposed to require.
    private(set) var isLoadingAPIKey = true

    let modelName = OnDeviceModel.general.id

    private let server = OnDeviceServer()
    private let logLevel: ServerConfiguration.LogLevel

    init() {
        let settings = ServerSettings.load()
        host = settings.host
        portText = String(settings.port)
        autoStart = settings.autoStart
        logLevel = settings.logLevel
        if !bindableAddresses.contains(host) {
            // The stored address belonged to a network this Mac has left.
            host = NetworkInterfaces.loopback
        }
    }

    // MARK: Settings

    var port: Int? {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)),
            ServerSettings.validPorts.contains(port)
        else { return nil }
        return port
    }

    var isReachableFromNetwork: Bool { host != NetworkInterfaces.loopback }

    var requiresAPIKey: Bool { !apiKey.isEmpty }

    var canStart: Bool { port != nil && !isTransitioning && !isLoadingAPIKey }

    func resetToDefaults() {
        host = ServerSettings.defaults.host
        portText = String(ServerSettings.defaults.port)
        autoStart = ServerSettings.defaults.autoStart
        apiKey = ""
        persistAPIKey()
    }

    func refreshAddresses() {
        bindableAddresses = NetworkInterfaces.bindableAddresses()
        if !bindableAddresses.contains(host) {
            host = NetworkInterfaces.loopback
        }
    }

    private var settings: ServerSettings? {
        port.map { ServerSettings(host: host, port: $0, autoStart: autoStart, logLevel: logLevel) }
    }

    private func persist() {
        settings?.save()
    }

    // MARK: Lifecycle

    /// Runs once at launch: the key has to be read before an auto-start uses it.
    func prepare() async {
        // Off the main actor, because the keychain may stop to ask the user.
        apiKey = await Task.detached { APIKeyStore.load() }.value ?? ""
        isLoadingAPIKey = false
        if autoStart && !isRunning {
            await start()
        }
    }

    func generateAPIKey() {
        apiKey = APIKeyStore.generate()
        persistAPIKey()
    }

    func persistAPIKey() {
        do {
            try APIKeyStore.save(apiKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // The server starts whether or not the model is available: a client then gets
    // a 503 that says what to do, instead of a refused connection, and requests
    // succeed by themselves once a download finishes.
    func start() async {
        guard let settings, !isRunning, !isLoadingAPIKey else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        refreshAvailability()
        persistAPIKey()
        let configuration = settings.configuration(apiKey: apiKey)
        do {
            try await server.start(configuration)
            activeConfiguration = configuration
            isRunning = true
            lastError = nil
        } catch {
            lastError = "Could not start on \(settings.host):\(settings.port): \(error.localizedDescription)"
        }
    }

    func stop() async {
        isTransitioning = true
        defer { isTransitioning = false }
        await server.stop()
        isRunning = false
        activeConfiguration = nil
    }

    func refreshAvailability() {
        availability = OnDeviceModel.general.availability
    }

    // MARK: What clients are told

    var baseURL: String {
        guard let activeConfiguration else { return settings?.configuration(apiKey: "").baseURL() ?? "" }
        // 0.0.0.0 is where the server listens, not an address a client can dial.
        let advertised = activeConfiguration.host == NetworkInterfaces.allInterfaces
            ? NetworkInterfaces.primaryLANAddress() ?? NetworkInterfaces.loopback
            : activeConfiguration.host
        return activeConfiguration.baseURL(advertisedHost: advertised)
    }

    var chatCompletionsURL: String { "\(baseURL)/chat/completions" }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
