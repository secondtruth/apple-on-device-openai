import SwiftUI

struct ServerSettingsSection: View {
    @Bindable var viewModel: ServerViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case port, apiKey
    }

    var body: some View {
        Section {
            Picker("Bind address", selection: $viewModel.host) {
                ForEach(viewModel.bindableAddresses, id: \.self) { address in
                    Text(address == NetworkInterfaces.allInterfaces ? "All interfaces (0.0.0.0)" : address)
                        .tag(address)
                }
            }
            if viewModel.isReachableFromNetwork && !viewModel.requiresAPIKey {
                Notice(
                    text: "Other devices on your network can reach this address, and no API key is set. "
                        + "Set one below, or use it on networks you trust.",
                    tint: .orange)
            }

            // Bordered, and as wide as its content gets: in a grouped form a
            // borderless field is indistinguishable from a read-only value.
            LabeledContent("Port") {
                TextField("Port", text: $viewModel.portText, prompt: Text(String(ServerSettings.defaults.port)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 72)
                    .focused($focusedField, equals: .port)
                    .onSubmit { viewModel.persistPort() }
            }
            if viewModel.port == nil {
                Notice(text: "Enter a port between 1 and 65535.", tint: .red)
            }

            apiKeyRow

            Toggle("Start server at launch", isOn: $viewModel.autoStart)
        } header: {
            Text("Server")
        } footer: {
            footer
        }
        // Text fields are saved when editing ends, not on every keystroke.
        .onChange(of: focusedField) { previous, _ in
            switch previous {
            case .port: viewModel.persistPort()
            case .apiKey: viewModel.persistAPIKey()
            case nil: break
            }
        }
        // The running server keeps the configuration it started with.
        .disabled(viewModel.isRunning || viewModel.isLoadingAPIKey)
    }

    private var apiKeyRow: some View {
        LabeledContent {
            HStack(spacing: 8) {
                SecureField("API key", text: $viewModel.apiKey, prompt: Text("None"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 200)
                    .focused($focusedField, equals: .apiKey)
                    .onSubmit { viewModel.persistAPIKey() }
                Button("Generate") { viewModel.generateAPIKey() }
                CopyButton(text: viewModel.apiKey, onCopy: viewModel.copyToClipboard)
                    .disabled(!viewModel.requiresAPIKey)
            }
        } label: {
            Text("API key")
            Text("Optional")
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(
                viewModel.isRunning
                    ? "Stop the server to change these settings."
                    : "Clients send the API key as their OpenAI key. It is kept in your login keychain and "
                        + "travels unencrypted over HTTP.")
            Spacer()
            Button("Reset to Defaults") { viewModel.resetToDefaults() }
                .buttonStyle(.link)
        }
    }
}
