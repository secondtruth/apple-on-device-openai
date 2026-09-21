import SwiftUI

/// A form row for a value the user is meant to paste into another program.
struct CopyableValueRow: View {
    let label: String
    let value: String
    /// What to show instead of the value, for secrets.
    var displayedValue: String?
    let onCopy: (String) -> Void

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                // Monospace, one step down: a value to transcribe, which must not
                // outweigh the label that explains it.
                Text(displayedValue ?? value)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                CopyButton(text: value, onCopy: onCopy)
            }
        }
    }
}

/// Copies on click and confirms it for a moment: the clipboard gives no
/// feedback of its own.
struct CopyButton: View {
    let text: String
    let onCopy: (String) -> Void
    @State private var didCopy = false

    var body: some View {
        Button {
            onCopy(text)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            // A fixed box: the two glyphs differ in size, and the row must not
            // twitch when one replaces the other.
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help("Copy")
        .accessibilityLabel("Copy")
    }
}
