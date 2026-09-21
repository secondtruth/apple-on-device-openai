import Vapor

func registerRoutes(on app: Application, serverVersion: String) {
    app.get("health") { _ in HTTPStatus.ok }

    app.get("status") { _ in ServerStatus(serverVersion: serverVersion) }

    let v1 = app.grouped("v1")

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
