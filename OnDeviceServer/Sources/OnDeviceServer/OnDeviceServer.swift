import Vapor

/// An OpenAI-compatible HTTP server in front of Apple's on-device language model.
///
/// The host application owns one instance and starts and stops it; everything
/// else in this package is reached through HTTP.
public actor OnDeviceServer {
    private var app: Application?

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

        // Replaces the defaults: Vapor's error middleware answers in a format no
        // OpenAI client understands.
        app.middleware = Middlewares()
        app.middleware.use(APIErrorMiddleware())
        registerRoutes(on: app, serverVersion: configuration.serverVersion)

        do {
            try await app.startup()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        self.app = app
        app.logger.notice("server started", metadata: [
            "host": "\(configuration.host)", "port": "\(configuration.port)",
            "version": "\(configuration.serverVersion)",
        ])
    }

    /// Stops accepting connections and lets running requests finish.
    public func stop() async {
        guard let app else { return }
        self.app = nil
        app.logger.notice("server stopping")
        try? await app.asyncShutdown()
    }
}
