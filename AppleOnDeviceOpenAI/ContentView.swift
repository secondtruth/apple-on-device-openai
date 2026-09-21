import SwiftUI

/// The server window, laid out as a grouped form like System Settings: the
/// platform then supplies the label column, the row separators and the
/// disabled states that a hand-built card has to imitate.
struct ContentView: View {
    @Bindable var viewModel: ServerViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            ServerStatusSection(viewModel: viewModel)
            if viewModel.isRunning {
                ConnectionDetailsSection(viewModel: viewModel)
            }
            ServerSettingsSection(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 720, minHeight: 360)
        // Apple Intelligence is switched on in System Settings and networks
        // change while the app is in the background, so both are most likely
        // stale when the user comes back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshEnvironment() }
        }
    }
}

#Preview {
    ContentView(viewModel: ServerViewModel())
}
