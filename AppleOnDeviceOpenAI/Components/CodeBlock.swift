import SwiftUI

struct CodeBlock: View {
    let code: String
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            Button("Copy Code") { onCopy(code) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}
