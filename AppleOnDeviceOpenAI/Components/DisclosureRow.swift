import SwiftUI

/// A form row that reveals a second row below it.
///
/// Built on a button rather than `DisclosureGroup`: inside a grouped form, the
/// native group did not react to the accessibility press action, so neither
/// VoiceOver nor UI automation could open it.
struct DisclosureRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")

        if isExpanded {
            content
        }
    }
}
