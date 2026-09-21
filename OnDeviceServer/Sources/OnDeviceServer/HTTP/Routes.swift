import Vapor

func registerRoutes(on app: Application, configuration: ServerConfiguration) {
    // Open even with an API key set: a liveness probe carries no credentials.
    app.get("health") { _ in HTTPStatus.ok }

    var api: any RoutesBuilder = app
    if let apiKey = configuration.apiKey, !apiKey.isEmpty {
        api = app.grouped(APIKeyMiddleware(expectedKey: apiKey))
    }

    let serverVersion = configuration.serverVersion
    api.get("status") { _ in ServerStatus(serverVersion: serverVersion) }

    let v1 = api.grouped("v1")

    v1.get("models") { _ in
        ModelList(data: OnDeviceModel.catalog.map(\.modelObject))
    }

    v1.get("models", ":id") { request in
        try OnDeviceModel.named(request.parameters.get("id")).modelObject
    }

    // Conversations with tool definitions and results outgrow Vapor's 16 KB default.
    v1.on(.POST, "chat", "completions", body: .collect(maxSize: "4mb")) { request in
        try await ChatCompletionsHandler().handle(request)
    }
}
