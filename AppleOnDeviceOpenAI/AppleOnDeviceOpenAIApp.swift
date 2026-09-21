import SwiftUI

@main
struct AppleOnDeviceOpenAIApp: App {
    @State private var viewModel = ServerViewModel()

    var body: some Scene {
        // One window, not a window group: there is one server, and a second
        // window would only show the same state twice.
        Window("Apple On-Device OpenAI", id: "server") {
            ContentView(viewModel: viewModel)
                .task { await viewModel.prepare() }
        }
        .defaultSize(width: 520, height: 560)
        .windowResizability(.contentMinSize)
    }
}
