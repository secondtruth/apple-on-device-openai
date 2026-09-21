import OnDeviceServer
import SwiftUI

struct ServerStatusSection: View {
    var viewModel: ServerViewModel

    var body: some View {
        GroupBox("Server Status") {
            VStack(alignment: .leading, spacing: 16) {
                runState
                modelState
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
                startStopButton
            }
        }
    }

    private var runState: some View {
        HStack {
            StatusDot(color: viewModel.isRunning ? .green : .secondary, size: 12)
            Text(viewModel.isRunning ? "Running" : "Stopped")
                .font(.headline)
            Spacer()
            if viewModel.isRunning {
                Text(viewModel.modelName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.blue)
            }
        }
    }

    private var modelState: some View {
        HStack {
            Text("Apple Intelligence:")
                .font(.subheadline)
                .fontWeight(.medium)
            StatusDot(color: viewModel.availability.isAvailable ? .green : .orange, size: 8)
            Text(viewModel.availability.isAvailable ? "Available" : "Not available")
                .font(.subheadline)
            Spacer()
            if !viewModel.availability.isAvailable {
                Button("Check Again") { viewModel.refreshAvailability() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var startStopButton: some View {
        HStack {
            if viewModel.isRunning {
                Button("Stop Server") { Task { await viewModel.stop() } }
                    .tint(.red)
                    .disabled(viewModel.isTransitioning)
            } else {
                Button("Start Server") { Task { await viewModel.start() } }
                    .tint(.green)
                    .disabled(!viewModel.canStart)
            }
            if viewModel.isTransitioning {
                ProgressView().controlSize(.small)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }
}
