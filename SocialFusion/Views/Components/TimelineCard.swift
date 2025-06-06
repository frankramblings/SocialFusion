import SwiftUI

/// Rounded card with border/shadow for timeline posts.
struct TimelineCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

#Preview {
    VStack {
        TimelineCard {
            VStack(alignment: .leading) {
                Text("Sample Post")
                    .font(.headline)
                Text("This is a sample post content to demonstrate the TimelineCard component.")
                    .font(.body)
                    .padding(.top, 4)
            }
        }

        TimelineCard {
            HStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                Text("Another card example")
            }
        }
    }
    .padding()
}
