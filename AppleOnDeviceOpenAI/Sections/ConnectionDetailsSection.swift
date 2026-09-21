import SwiftUI

/// What a client needs to be pointed at this server.
struct ConnectionDetailsSection: View {
    var viewModel: ServerViewModel

    var body: some View {
        GroupBox("OpenAI API Integration") {
            VStack(spacing: 16) {
                CopyableValueRow(
                    title: "Base URL", subtitle: "For OpenAI client libraries",
                    value: viewModel.baseURL, onCopy: viewModel.copyToClipboard)
                Divider()
                CopyableValueRow(
                    title: "Chat Completions", subtitle: "Direct API endpoint",
                    value: viewModel.chatCompletionsURL, onCopy: viewModel.copyToClipboard)
                Divider()
                CopyableValueRow(
                    title: "Model Name", subtitle: "Use this in your API requests",
                    value: viewModel.modelName, onCopy: viewModel.copyToClipboard)
            }
        }

        GroupBox("Quick Start") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Python Example:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                CodeBlock(code: pythonExample, onCopy: viewModel.copyToClipboard)
            }
        }
    }

    private var pythonExample: String {
        """
        from openai import OpenAI

        client = OpenAI(
            base_url="\(viewModel.baseURL)",
            api_key="not-needed"
        )

        response = client.chat.completions.create(
            model="\(viewModel.modelName)",
            messages=[{"role": "user", "content": "Hello!"}]
        )
        """
    }
}
