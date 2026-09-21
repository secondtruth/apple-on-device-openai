import Vapor

/// An OpenAI-compatible HTTP server in front of Apple's on-device language model.
///
/// The host application owns one instance and starts and stops it; everything
/// else in this package is reached through HTTP.
public actor OnDeviceServer {
    private var app: Application?
    private var activity: (any NSObjectProtocol)?

    public init() {}

    public var isRunning: Bool { app != nil }

    /// Binds the port and returns once the server accepts connections.
    /// Throws when the address is unavailable, e.g. the port is taken.
    public func start(_ configuration: ServerConfiguration) async throws {
        guard app == nil else { return }
        LogBootstrap.once()

        // Vapor parses the process arguments as its own commands by default; the
        // host app's arguments are not meant for it.
        let environment = Environment(name: "production", arguments: ["serve"])
        let app = try await Application.make(environment)
        app.logger.logLevel = configuration.logLevel.loggerLevel
        app.http.server.configuration.hostname = configuration.host
        app.http.server.configuration.port = configuration.port
        app.http.server.configuration.serverName = "apple-on-device-openai/\(configuration.serverVersion)"

        Self.configure(app, with: configuration)

        do {
            try await app.startup()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        self.app = app
        activity = Self.beginServingActivity()
        app.logger.notice("server started", metadata: [
            "host": "\(configuration.host)", "port": "\(configuration.port)",
            "version": "\(configuration.serverVersion)",
            "api_key_required": "\(configuration.apiKey?.isEmpty == false)",
        ])
    }

    /// Everything about the application that does not involve a socket.
    static func configure(_ app: Application, with configuration: ServerConfiguration) {
        // Replaces the defaults: Vapor's error middleware answers in a format no
        // OpenAI client understands.
        app.middleware = Middlewares()
        app.middleware.use(APIErrorMiddleware())
        registerRoutes(on: app, configuration: configuration)
    }

    /// Stops accepting connections and lets running requests finish.
    public func stop() async {
        guard let app else { return }
        self.app = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        app.logger.notice("server stopping")
        try? await app.asyncShutdown()
    }

    // The host is a GUI app, and macOS naps a GUI app nobody is using: after a
    // few idle minutes in the background its threads drop to the lowest
    // priority and requests stall for minutes. A server has no
    // such idle state. The assertion lifts App Nap while it runs, but still lets
    // the Mac go to sleep: whether it stays awake is the owner's power policy.
    private static func beginServingActivity() -> any NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Serving OpenAI-compatible API requests")
    }
}
