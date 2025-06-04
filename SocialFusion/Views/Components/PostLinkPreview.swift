import SwiftUI

/// A view that displays a link preview for a post
struct PostLinkPreview: View {
    let url: URL
    let title: String
    let description: String?
    let imageURL: URL?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Preview image if available
                if let imageURL = imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 200)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 200)
                                .clipped()
                        case .failure:
                            Image(systemName: "link")
                                .font(.largeTitle)
                                .frame(height: 200)
                                .foregroundColor(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                // Preview content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    if let description = description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }

                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
struct PostLinkPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Preview with image
            PostLinkPreview(
                url: URL(string: "https://example.com")!,
                title: "Example Website",
                description:
                    "This is an example website with a description that might be quite long and need to be truncated after a few lines.",
                imageURL: URL(string: "https://picsum.photos/400/200"),
                onTap: {}
            )

            // Preview without image
            PostLinkPreview(
                url: URL(string: "https://example.com")!,
                title: "Example Website",
                description: "This is an example website without an image.",
                imageURL: nil,
                onTap: {}
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
