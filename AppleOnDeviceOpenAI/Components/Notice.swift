import SwiftUI

/// A form row for a condition the user should act on.
struct Notice<Tint: ShapeStyle>: View {
    let text: String
    let tint: Tint

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
        }
        .font(.callout)
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
