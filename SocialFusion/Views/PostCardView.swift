import AVKit
import SwiftUI
// Import required for HTMLFormatter
import UIKit

struct PostCardView: View {
    let post: Post
    @State private var showDetailView = false
    @State private var selectedMedia: MediaAttachment? = nil
    @State private var showMediaFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with author info and platform indicator
            HStack {
                // Author avatar with platform badge
                ZStack {
                    if let avatarURL = post.author.avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.gray)
                    }

                    // Platform badge in bottom-right corner
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            PostPlatformBadge(platform: post.platform)
                        }
                    }
                    .padding(0)
                    .frame(width: 48, height: 48)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("@\(post.author.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Post time
                Text(timeAgo(from: post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            // Post content - simple text with HTML cleaning
            Text(cleanHtmlString(post.content))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 5)
                .onTapGesture {
                    showDetailView = true
                }

            // Media attachments if any - now full width
            if !post.mediaAttachments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(post.mediaAttachments) { attachment in
                        MediaView(
                            attachment: attachment,
                            showFullscreen: {
                                selectedMedia = attachment
                                showMediaFullscreen = true
                            })
                    }
                }
            }

            // Action buttons
            HStack(spacing: 24) {
                // Reply
                Button(action: {
                    showDetailView = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                        Text("\(post.replyCount)")
                    }
                    .foregroundColor(.secondary)
                }

                // Repost
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(
                            systemName: post.isReposted
                                ? "arrow.triangle.2.circlepath.fill" : "arrow.triangle.2.circlepath"
                        )
                        Text("\(post.repostCount)")
                    }
                    .foregroundColor(post.isReposted ? Color(post.platform.color) : .secondary)
                }

                // Like
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        Text("\(post.likeCount)")
                    }
                    .foregroundColor(post.isLiked ? .red : .secondary)
                }

                Spacer()

                // Share
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .sheet(isPresented: $showDetailView) {
            PostDetailView(post: post)
        }
        .sheet(isPresented: $showMediaFullscreen) {
            if let media = selectedMedia {
                FullscreenMediaView(attachment: media)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Helper function to format dates as relative time
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // Basic HTML cleanup function
    private func cleanHtmlString(_ html: String) -> String {
        // Replace common HTML entities
        var result =
            html
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Remove HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil)

        return result
    }
}

// Platform badge component with improved appearance
struct PostPlatformBadge: View {
    let platform: SocialPlatform

    private func getLogoName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "MastodonLogo"
        case .bluesky:
            return "BlueskyLogo"
        }
    }

    private func getPlatformColor() -> Color {
        switch platform {
        case .mastodon:
            return Color("PrimaryColor")
        case .bluesky:
            return Color("SecondaryColor")
        }
    }

    var body: some View {
        ZStack {
            // Remove the white circle background
            // Just use the platform logo with a shadow for visibility against the avatar
            Image(getLogoName(for: platform))
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundColor(getPlatformColor())
                .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 0)
        }
        .frame(width: 16, height: 16)
        .offset(x: 4, y: 4)  // Keep the offset to position away from edge
    }
}

// A view for displaying media attachments
struct MediaView: View {
    let attachment: MediaAttachment
    let showFullscreen: () -> Void

    @State private var aspectRatio: CGFloat = 16 / 9  // Default aspect ratio

    var body: some View {
        Group {
            if attachment.type == .image {
                AsyncImage(url: attachment.url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                // Get the image dimensions if possible
                                if let data = try? Data(contentsOf: attachment.url),
                                    let uiImage = UIImage(data: data)
                                {
                                    let imageSize = uiImage.size
                                    aspectRatio = imageSize.width / imageSize.height
                                }
                            }
                    } else if phase.error != nil {
                        Color.gray
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                            )
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: min(UIScreen.main.bounds.width / aspectRatio, 300))
                .cornerRadius(8)
                .clipped()
                .onTapGesture {
                    showFullscreen()
                }
            } else if attachment.type == .video || attachment.type == .animatedGIF {
                VideoPlayer(player: AVPlayer(url: attachment.url))
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: min(UIScreen.main.bounds.width / aspectRatio, 300))
                    .cornerRadius(8)
                    .onTapGesture {
                        showFullscreen()
                    }
            }
        }
    }
}

// View for fullscreen media presentation
struct FullscreenMediaView: View {
    let attachment: MediaAttachment
    @Environment(\.presentationMode) var presentationMode
    @State private var showShareSheet = false
    @State private var imageToShare: UIImage?

    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .shadow(radius: 3)
                    }
                }

                Spacer()

                if attachment.type == .image {
                    AsyncImage(url: attachment.url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .onAppear {
                                    // Load the image for sharing
                                    if let data = try? Data(contentsOf: attachment.url),
                                        let uiImage = UIImage(data: data)
                                    {
                                        imageToShare = uiImage
                                    }
                                }
                        } else if phase.error != nil {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                Text("Failed to load image")
                            }
                            .foregroundColor(.white)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(2)
                        }
                    }
                    .onLongPressGesture {
                        showShareSheet = true
                    }
                } else if attachment.type == .video || attachment.type == .animatedGIF {
                    VideoPlayer(player: AVPlayer(url: attachment.url))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onLongPressGesture {
                            showShareSheet = true
                        }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .edgesIgnoringSafeArea(.all)
            .sheet(isPresented: $showShareSheet) {
                if let image = imageToShare {
                    ShareSheet(items: [image])
                } else {
                    ShareSheet(items: [attachment.url])
                }
            }
        }
    }
}

// Helper view for sharing
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Post detail view for expanded post display
struct PostDetailView: View {
    let post: Post
    @Environment(\.presentationMode) var presentationMode
    @State private var replyText = ""
    @State private var selectedMedia: MediaAttachment? = nil
    @State private var showMediaFullscreen = false
    @State private var replies: [Post] = []
    @State private var isLoadingReplies = false
    @State private var replyError: Error? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        if let avatarURL = post.author.avatarURL {
                            AsyncImage(url: avatarURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 56, height: 56)
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.author.displayName)
                                .font(.title3)
                                .fontWeight(.bold)

                            Text("@\(post.author.username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        PostPlatformBadge(platform: post.platform)
                            .scaleEffect(1.3)
                    }
                    .padding(.horizontal)

                    // Content
                    Text(cleanHtmlString(post.content))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)

                    // Media
                    if !post.mediaAttachments.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(post.mediaAttachments) { attachment in
                                MediaView(
                                    attachment: attachment,
                                    showFullscreen: {
                                        selectedMedia = attachment
                                        showMediaFullscreen = true
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Post metadata
                    HStack {
                        Text(formatDate(post.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal)

                    Divider()

                    // Engagement metrics
                    HStack(spacing: 24) {
                        VStack {
                            Text("\(post.replyCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Replies")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack {
                            Text("\(post.repostCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Reposts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack {
                            Text("\(post.likeCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Likes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    Divider()

                    // Action buttons - larger and more prominent
                    HStack(spacing: 0) {
                        // Reply
                        Button(action: {}) {
                            VStack {
                                Image(systemName: "bubble.left")
                                    .font(.title2)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .foregroundColor(.secondary)

                        // Repost
                        Button(action: {}) {
                            VStack {
                                Image(
                                    systemName: post.isReposted
                                        ? "arrow.triangle.2.circlepath.fill"
                                        : "arrow.triangle.2.circlepath"
                                )
                                .font(.title2)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .foregroundColor(post.isReposted ? Color(post.platform.color) : .secondary)

                        // Like
                        Button(action: {}) {
                            VStack {
                                Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                    .font(.title2)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .foregroundColor(post.isLiked ? .red : .secondary)

                        // Share
                        Button(action: {}) {
                            VStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)

                    Divider()

                    // Reply input field
                    VStack {
                        TextField("Reply to this post...", text: $replyText)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(20)

                        HStack {
                            Spacer()
                            Button("Reply") {
                                // Reply action
                                replyText = ""
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color(post.platform.color))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .disabled(replyText.isEmpty)
                            .opacity(replyText.isEmpty ? 0.6 : 1)
                        }
                    }
                    .padding()

                    // Replies section
                    if isLoadingReplies {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                            Spacer()
                        }
                    } else {
                        if !replies.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Conversation")
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top, 8)

                                ForEach(replies) { reply in
                                    ReplyRow(reply: reply)
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)

                                    if reply.id != replies.last?.id {
                                        Divider()
                                            .padding(.leading, 64)
                                    }
                                }
                            }
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .padding(.bottom)
                        } else if let error = replyError {
                            VStack {
                                Text("Could not load replies")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button("Try Again") {
                                    loadReplies()
                                }
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if post.replyCount > 0 {
                            Button(action: loadReplies) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Load \(post.replyCount) replies")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.tertiarySystemBackground))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            )
            .sheet(isPresented: $showMediaFullscreen) {
                if let media = selectedMedia {
                    FullscreenMediaView(attachment: media)
                }
            }
            .onAppear {
                // Automatically load replies when the view appears
                if post.replyCount > 0 && replies.isEmpty {
                    loadReplies()
                }
            }
        }
    }

    private func loadReplies() {
        // In a real app, this would fetch replies from the API
        isLoadingReplies = true
        replyError = nil

        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            do {
                // In a real app, this would be an API call
                // For now, we'll generate some sample replies
                self.replies = generateSampleReplies(for: post)
                self.isLoadingReplies = false
            } catch {
                self.replyError = error
                self.isLoadingReplies = false
            }
        }
    }

    private func generateSampleReplies(for post: Post) -> [Post] {
        // Create sample replies for the post
        let replyCount = min(post.replyCount, 5)  // Limit to 5 sample replies

        var sampleReplies: [Post] = []

        for i in 1...replyCount {
            let isInThread = i % 2 == 0  // Some replies are in thread
            let replyTo = isInThread ? sampleReplies.last : post

            let reply = Post(
                id: "reply_\(post.id)_\(i)",
                platform: post.platform,
                author: Author(
                    id: "replier_\(i)",
                    username: "user\(i)",
                    displayName: "User \(i)",
                    profileImageURL: URL(string: "https://placekitten.com/\(200+i)/\(200+i)"),
                    platform: post.platform,
                    platformSpecificId: "replier_\(i)_\(post.platform.rawValue.lowercased())"
                ),
                content:
                    "This is a reply to the post. Reply #\(i) with some sample text to demonstrate the conversation thread. \(isInThread ? "This is a reply to another reply." : "This is a direct reply to the original post.")",
                mediaAttachments: [],
                createdAt: Date().addingTimeInterval(-Double(i) * 300),  // Each reply is 5 minutes apart
                likeCount: Int.random(in: 0...50),
                repostCount: Int.random(in: 0...10),
                replyCount: 0,
                isLiked: Bool.random(),
                isReposted: Bool.random(),
                platformSpecificId: "reply_\(post.id)_\(i)_\(post.platform.rawValue.lowercased())"
            )

            sampleReplies.append(reply)
        }

        return sampleReplies
    }

    // Helper method to format the date in a readable format
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // HTML cleanup function - same as in PostCardView
    private func cleanHtmlString(_ html: String) -> String {
        // Replace common HTML entities
        var result =
            html
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Remove HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil)

        return result
    }
}

// Reply row for conversation threads
struct ReplyRow: View {
    let reply: Post
    @State private var showDetailView = false

    var body: some View {
        VStack {
            Button(action: {
                showDetailView = true
            }) {
                HStack(alignment: .top, spacing: 12) {
                    // Author avatar
                    if let avatarURL = reply.author.avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Author info
                        HStack {
                            Text(reply.author.displayName)
                                .font(.subheadline)
                                .fontWeight(.bold)

                            Text("@\(reply.author.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(timeAgo(from: reply.createdAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // Reply content
                        Text(cleanHtmlString(reply.content))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        // Action buttons - minimal version
                        HStack(spacing: 24) {
                            // Reply
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.caption)
                                Text(reply.replyCount > 0 ? "\(reply.replyCount)" : "")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            // Repost
                            HStack(spacing: 4) {
                                Image(
                                    systemName: reply.isReposted
                                        ? "arrow.triangle.2.circlepath.fill"
                                        : "arrow.triangle.2.circlepath"
                                )
                                .font(.caption)
                                Text(reply.repostCount > 0 ? "\(reply.repostCount)" : "")
                                    .font(.caption)
                            }
                            .foregroundColor(
                                reply.isReposted ? Color(reply.platform.color) : .secondary)

                            // Like
                            HStack(spacing: 4) {
                                Image(systemName: reply.isLiked ? "heart.fill" : "heart")
                                    .font(.caption)
                                Text(reply.likeCount > 0 ? "\(reply.likeCount)" : "")
                                    .font(.caption)
                            }
                            .foregroundColor(reply.isLiked ? .red : .secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .foregroundColor(.primary)
            }
            .sheet(isPresented: $showDetailView) {
                PostDetailView(post: reply)
            }
        }
    }

    // Helper function to format dates as relative time
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // Basic HTML cleanup function
    private func cleanHtmlString(_ html: String) -> String {
        // Replace common HTML entities
        var result =
            html
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Remove HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression, range: nil)

        return result
    }
}

struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                PostCardView(post: Post.samplePosts[0])  // Mastodon
                PostCardView(post: Post.samplePosts[1])  // Bluesky with image
            }
            .padding()
        }
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.light)

        // Preview detail view
        PostDetailView(post: Post.samplePosts[1])
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
    }
}
// Extension to create UIColor from hex string if it doesn't already exist in this file
extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgb & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
