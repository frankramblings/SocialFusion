import SwiftUI

/// A view that displays the content of a post with hashtags and mentions
struct PostContent: View {
    let content: String
    let hashtags: [String]
    let mentions: [String]
    let onHashtagTap: (String) -> Void
    let onMentionTap: (String) -> Void

    var body: some View {
        Text(attributedContent)
            .font(.body)
            .textSelection(.enabled)
    }

    private var attributedContent: AttributedString {
        var attributedString = AttributedString(content)

        // Apply hashtag styling
        for hashtag in hashtags {
            if let range = attributedString.range(of: "#\(hashtag)") {
                attributedString[range].foregroundColor = .blue
                attributedString[range].underlineStyle = .single
            }
        }

        // Apply mention styling
        for mention in mentions {
            if let range = attributedString.range(of: "@\(mention)") {
                attributedString[range].foregroundColor = .blue
                attributedString[range].underlineStyle = .single
            }
        }

        return attributedString
    }
}

/// A view that displays a content warning with expand/collapse functionality
private struct ContentWarningView: View {
    let text: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Warning header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text("Content Warning")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }

            // Warning text
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Show/hide button
            Button(action: { isExpanded.toggle() }) {
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview
struct PostContent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Regular post with hashtags and mentions
            PostContent(
                content: "This is a test post with #hashtags and @mentions",
                hashtags: ["hashtags"],
                mentions: ["mentions"],
                onHashtagTap: { _ in },
                onMentionTap: { _ in }
            )

            // Post with multiple hashtags and mentions
            PostContent(
                content: "Check out #swift #ios and follow @apple @swift",
                hashtags: ["swift", "ios"],
                mentions: ["apple", "swift"],
                onHashtagTap: { _ in },
                onMentionTap: { _ in }
            )

            // Post with no hashtags or mentions
            PostContent(
                content: "This is a regular post without any special formatting",
                hashtags: [],
                mentions: [],
                onHashtagTap: { _ in },
                onMentionTap: { _ in }
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
