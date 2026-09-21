import OnDeviceServer
import SwiftUI

struct ServerStatusSection: View {
    var viewModel: ServerViewModel

    var body: some View {
        Section {
            runState
            LabeledContent("Apple Intelligence") {
                HStack(spacing: 6) {
                    StatusDot(color: viewModel.availability.isAvailable ? .green : .orange)
                    Text(viewModel.availability.isAvailable ? "Available" : "Not available")
                }
            }
            if let explanation = viewModel.availability.explanation {
                Notice(text: explanation, tint: .orange)
            }
            if viewModel.isLoadingAPIKey {
                Notice(
                    text: "Waiting for the keychain to release the API key. macOS may be asking for "
                        + "permission in a separate dialog.",
                    tint: .secondary)
            }
            if let error = viewModel.lastError {
                Notice(text: error, tint: .red)
            }
        }
    }

    private var runState: some View {
        HStack(spacing: 10) {
            StatusDot(color: viewModel.isRunning ? .green : .secondary, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isRunning ? "Running" : "Stopped")
                    .font(.headline)
                Text(viewModel.listeningDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if viewModel.isTransitioning {
                ProgressView().controlSize(.small)
            }
            if viewModel.isRunning {
                Button("Stop") { Task { await viewModel.stop() } }
                    .disabled(viewModel.isTransitioning)
            } else {
                Button("Start Server") { Task { await viewModel.start() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canStart)
            }
        }
        .padding(.vertical, 4)
    }
}
