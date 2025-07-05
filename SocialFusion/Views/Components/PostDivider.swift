import SwiftUI

/// Enhanced post divider with improved visibility and proper text alignment
struct PostDivider: View {
    @Environment(\.colorScheme) var colorScheme

    /// The leading padding to align with post text (typically 56pt for avatar + spacing)
    let leadingPadding: CGFloat

    /// Whether this is a prominent divider (e.g., between sections)
    let isProminent: Bool

    init(leadingPadding: CGFloat = 56, isProminent: Bool = false) {
        self.leadingPadding = leadingPadding
        self.isProminent = isProminent
    }

    var body: some View {
        // Enhanced divider with subtle gradient for better visibility
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        dividerColor.opacity(0.3),
                        dividerColor,
                        dividerColor,
                        dividerColor.opacity(0.3),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: dividerHeight)
            .padding(.leading, leadingPadding)
    }

    private var dividerColor: Color {
        if isProminent {
            return colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.45)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.35)
        }
    }

    private var dividerHeight: CGFloat {
        isProminent ? 1.0 : 0.75
    }
}

/// Alternative post divider styles for different contexts
extension PostDivider {
    /// Full-width divider for section breaks
    static func section() -> some View {
        PostDivider(leadingPadding: 0, isProminent: true)
    }

    /// Text-aligned divider for timeline posts (standard)
    static func timeline() -> some View {
        PostDivider(leadingPadding: 56, isProminent: false)
    }

    /// Thread divider for post details
    static func thread(leadingPadding: CGFloat = 52) -> some View {
        PostDivider(leadingPadding: leadingPadding, isProminent: false)
    }
}

#Preview {
    VStack(spacing: 20) {
        VStack {
            Text("Sample post text that demonstrates alignment")
                .padding(.leading, 56)
            PostDivider.timeline()
        }

        VStack {
            Text("Full width section break below")
            PostDivider.section()
        }

        VStack {
            Text("Thread discussion item")
                .padding(.leading, 52)
            PostDivider.thread()
        }
    }
    .padding()
}
