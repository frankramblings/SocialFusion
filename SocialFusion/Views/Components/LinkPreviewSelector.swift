import SwiftUI

struct LinkPreviewSelector: View {
    let links: [URL]
    let postId: String
    @State private var selectedURL: URL?
    @State private var showMenu = false
    @State private var arePreviewsDisabled = false

    var body: some View {
        VStack(alignment: .leading) {
            if !links.isEmpty && !arePreviewsDisabled {
                HStack {
                    Text("Link Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Menu {
                        // Option to disable all previews
                        Button(
                            role: .destructive,
                            action: {
                                disablePreviews()
                            }
                        ) {
                            Label("Disable Preview", systemImage: "eye.slash")
                        }

                        Divider()

                        // For each link, create a menu option
                        ForEach(links, id: \.absoluteString) { link in
                            Button(action: {
                                selectLink(link)
                            }) {
                                HStack {
                                    if selectedURL == link {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(link.host ?? link.absoluteString)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let selectedURL = selectedURL, let host = selectedURL.host {
                                Text(host)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
            }
        }
        .onAppear {
            // Check if we have a previously selected URL for this post
            if let existing = PreviewLinkSelection.shared.getSelectedLink(for: postId) {
                self.selectedURL = existing
            } else if !links.isEmpty {
                // Default to the first link if none is selected
                self.selectedURL = links.first
                PreviewLinkSelection.shared.setSelectedLink(url: links.first!, for: postId)
            }

            // Check if previews are disabled for this post
            self.arePreviewsDisabled = PreviewLinkSelection.shared.arePreviewsDisabled(for: postId)
        }
    }

    private func selectLink(_ url: URL) {
        self.selectedURL = url
        PreviewLinkSelection.shared.setSelectedLink(url: url, for: postId)
    }

    private func disablePreviews() {
        self.arePreviewsDisabled = true
        PreviewLinkSelection.shared.disablePreviews(for: postId)
    }
}

#Preview {
    VStack(spacing: 20) {
        LinkPreviewSelector(
            links: [
                URL(string: "https://example.com")!,
                URL(string: "https://apple.com")!,
                URL(string: "https://swift.org")!,
            ], postId: "preview-1")

        LinkPreviewSelector(
            links: [
                URL(string: "https://developer.apple.com")!
            ], postId: "preview-2")

        LinkPreviewSelector(links: [], postId: "preview-3")
    }
    .padding()
    .previewLayout(.sizeThatFits)
}
