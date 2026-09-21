import SwiftUI

struct EndpointRow: View {
    let method: String
    let path: String
    let description: String

    var body: some View {
        HStack {
            Text(method)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(methodColor)
            Text(path)
                .font(.system(.body, design: .monospaced))
            Text("•")
                .foregroundStyle(.secondary)
            Text(description)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var methodColor: Color {
        method == "POST" ? .blue : .green
    }
}
