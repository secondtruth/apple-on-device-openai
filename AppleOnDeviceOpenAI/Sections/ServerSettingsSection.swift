import SwiftUI

struct ServerSettingsSection: View {
    @Bindable var viewModel: ServerViewModel

    var body: some View {
        GroupBox("Server Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Bind Address", selection: $viewModel.host) {
                        ForEach(viewModel.bindableAddresses, id: \.self) { address in
                            Text(address == NetworkInterfaces.allInterfaces ? "All interfaces (0.0.0.0)" : address)
                                .tag(address)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Rescan Network Interfaces", systemImage: "arrow.clockwise") {
                        viewModel.refreshAddresses()
                    }
                    .labelStyle(.iconOnly)
                    .help("Rescan network interfaces")
                }

                if viewModel.isReachableFromNetwork {
                    Notice(
                        text: "This address makes the server reachable by other devices on your network, "
                            + "and it has no authentication. Use it on networks you trust.",
                        tint: .orange)
                }

                HStack {
                    Text("Port:")
                        .frame(width: 60, alignment: .leading)
                    TextField(String(ServerSettings.defaults.port), text: $viewModel.portText)
                        .textFieldStyle(.roundedBorder)
                }
                if viewModel.port == nil {
                    Text("Enter a port between 1 and 65535.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Start the server when the app launches", isOn: $viewModel.autoStart)

                HStack {
                    Spacer()
                    Button("Reset to Defaults") { viewModel.resetToDefaults() }
                        .buttonStyle(.borderless)
                }
            }
            // The running server keeps the configuration it started with.
            .disabled(viewModel.isRunning)
        }
    }
}
