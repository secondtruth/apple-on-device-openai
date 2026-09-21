import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ServerViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                ServerStatusSection(viewModel: viewModel)
                if viewModel.isRunning {
                    ConnectionDetailsSection(viewModel: viewModel)
                }
                ServerSettingsSection(viewModel: viewModel)
                if viewModel.isRunning {
                    EndpointsSection()
                }
            }
            .padding()
        }
        .frame(maxWidth: 600)
        // Apple Intelligence is switched on in System Settings, so the state has
        // most likely changed when the user comes back from there.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshAvailability() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Apple On-Device OpenAI API")
                .font(.title)
                .fontWeight(.semibold)
            Text("Local Apple Intelligence through OpenAI-compatible endpoints")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ContentView(viewModel: ServerViewModel())
}
