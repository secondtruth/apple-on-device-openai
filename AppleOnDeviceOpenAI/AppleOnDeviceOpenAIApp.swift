import SwiftUI

@main
struct AppleOnDeviceOpenAIApp: App {
    @State private var viewModel = ServerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .task { await viewModel.prepare() }
        }
    }
}
