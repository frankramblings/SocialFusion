import SwiftUI

/// A view that displays an expanding banner for reply contexts
struct ExpandingReplyBanner: View {
    let post: Post
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reply indicator
            if post.inReplyToUsername != nil {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Replying to \(post.inReplyToUsername ?? "someone")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Expanded content (placeholder for now)
                if isExpanded {
                    VStack {
                        Text("Parent post content would appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
        .onAppear {
            print("ExpandingReplyBanner appeared")
        }
        .onDisappear {
            print("ExpandingReplyBanner disappeared")
        }
    }
}

#Preview {
    ExpandingReplyBanner(
        post: Post(
            id: "1",
            content: "Sample reply",
            authorName: "Author",
            authorUsername: "author",
            authorProfilePictureURL: "",
            createdAt: Date(),
            platform: .bluesky,
            originalURL: "",
            attachments: [],
            mentions: [],
            tags: [],
            platformSpecificId: "1",
            inReplyToUsername: "someone",
            quotedPostUri: nil,
            quotedPostAuthorHandle: nil,
            cid: nil
        ))
}
