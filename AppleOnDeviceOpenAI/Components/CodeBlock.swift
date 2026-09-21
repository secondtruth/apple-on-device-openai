import SwiftUI

struct CodeBlock: View {
    let code: String
    let onCopy: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            CopyButton(text: code, onCopy: onCopy)
                .padding(6)
        }
    }
}
