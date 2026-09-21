import SwiftUI

/// A labelled value the user is meant to paste into another program.
struct CopyableValueRow: View {
    let title: String
    let subtitle: String
    let value: String
    /// What to show instead of the value, for secrets.
    var displayedValue: String?
    let onCopy: (String) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Text(displayedValue ?? value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Copy") { onCopy(value) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
