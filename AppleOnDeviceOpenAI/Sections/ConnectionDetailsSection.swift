import SwiftUI

/// What a client needs to be pointed at this server.
struct ConnectionDetailsSection: View {
    var viewModel: ServerViewModel

    var body: some View {
        Section("Connect a Client") {
            CopyableValueRow(label: "Base URL", value: viewModel.baseURL, onCopy: viewModel.copyToClipboard)
            CopyableValueRow(label: "Model", value: viewModel.modelName, onCopy: viewModel.copyToClipboard)
            if viewModel.requiresAPIKey {
                // Masked, but copyable: this is where the key is needed while the
                // server runs and the settings below are locked.
                CopyableValueRow(
                    label: "API key", value: viewModel.apiKey,
                    displayedValue: String(repeating: "•", count: 12), onCopy: viewModel.copyToClipboard)
            } else {
                LabeledContent("API key", value: "Not required — any value works")
            }

            DisclosureRow(title: "Python example") {
                CodeBlock(code: pythonExample, onCopy: viewModel.copyToClipboard)
            }
            DisclosureRow(title: "Endpoints") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.endpoints, id: \.path) { endpoint in
                        HStack(spacing: 8) {
                            Text(endpoint.method)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(endpoint.path)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Spacer()
                            Text(endpoint.purpose)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private static let endpoints: [(method: String, path: String, purpose: String)] = [
        ("POST", "/v1/chat/completions", "Chat completions"),
        ("GET", "/v1/models", "Models and availability"),
        ("GET", "/status", "Model status"),
        ("GET", "/health", "Liveness, no key needed"),
    ]

    private var pythonExample: String {
        """
        from openai import OpenAI

        client = OpenAI(
            base_url="\(viewModel.baseURL)",
            api_key="\(viewModel.requiresAPIKey ? "<your API key>" : "not-needed")",
        )

        response = client.chat.completions.create(
            model="\(viewModel.modelName)",
            messages=[{"role": "user", "content": "Hello!"}],
        )
        """
    }
}
