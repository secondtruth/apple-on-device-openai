import SwiftUI

/// A tinted box for a condition the user should act on.
struct Notice: View {
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(tint)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct StatusDot: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
