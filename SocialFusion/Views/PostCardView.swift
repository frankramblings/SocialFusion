import AVKit
import SwiftUI
// Import required for HTMLFormatter
import UIKit

struct PostCardView: View {
    let post: Post
    @State private var showDetailView = false
    @State private var selectedMedia: Post.Attachment? = nil
    @State private var showMediaFullscreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with author info and platform indicator
            HStack {
                // Author avatar with platform badge
                PostAuthorImageView(
                    authorProfilePictureURL: post.authorProfilePictureURL,
                    platform: post.platform
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("@\(post.authorUsername)")
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
            if !post.attachments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(post.attachments, id: \.url) { attachment in
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
                        Text("0")
                    }
                    .foregroundColor(.secondary)
                }

                // Repost
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("0")
                    }
                    .foregroundColor(.secondary)
                }

                // Like
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                        Text("0")
                    }
                    .foregroundColor(.secondary)
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
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents(
            [.minute, .hour, .day, .weekOfMonth, .month, .year], from: date, to: now)

        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }

        if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }

        if let weeks = components.weekOfMonth, weeks > 0 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }

        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }

        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }

        return "Just now"
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
                .frame(width: 16, height: 16)
                .foregroundColor(getPlatformColor())
                .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 0)
        }
        .frame(width: 20, height: 20)
        .offset(x: 6, y: 6)  // Increased offset to move badge more to the right and down
    }
}

// A view for displaying media attachments
struct MediaView: View {
    let attachment: Post.Attachment
    let showFullscreen: () -> Void

    @State private var aspectRatio: CGFloat = 16 / 9  // Default aspect ratio

    var body: some View {
        Group {
            if attachment.type == .image {
                AsyncImage(url: URL(string: attachment.url)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .onAppear {
                                // Get the image dimensions if possible
                                if let url = URL(string: attachment.url),
                                    let data = try? Data(contentsOf: url),
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
            } else if attachment.type == .video {
                if let url = URL(string: attachment.url) {
                    VideoPlayer(player: AVPlayer(url: url))
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
}

// View for fullscreen media presentation
struct FullscreenMediaView: View {
    let attachment: Post.Attachment
    @Environment(\.presentationMode) var presentationMode
    @State private var showShareSheet = false
    @State private var imageToShare: UIImage?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if attachment.type == .image {
                    AsyncImage(url: URL(string: attachment.url)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .edgesIgnoringSafeArea(.all)
                        } else if phase.error != nil {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                Text("Failed to load image")
                                    .padding(.top)
                            }
                            .foregroundColor(.white)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(2)
                                .tint(.white)
                        }
                    }
                } else if attachment.type == .video {
                    if let url = URL(string: attachment.url) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .edgesIgnoringSafeArea(.all)
                    } else {
                        Text("Invalid video URL")
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                },
                trailing: Button(action: {
                    showShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShareSheet) {
                if let url = URL(string: attachment.url) {
                    ShareSheet(items: [url])
                }
            }
        }
    }
}

// Helper view for share sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// A Reply view for the PostDetailView
struct ReplyView: View {
    let reply: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Author avatar
                PostAuthorImageView(
                    authorProfilePictureURL: reply.authorProfilePictureURL,
                    platform: reply.platform
                )
                .frame(width: 36, height: 36)  // Smaller size for replies

                VStack(alignment: .leading, spacing: 4) {
                    // Author info
                    HStack {
                        Text(reply.authorName)
                            .font(.subheadline)
                            .fontWeight(.bold)

                        Text("@\(reply.authorUsername)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(timeAgo(from: reply.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Content
                    Text(cleanHtmlString(reply.content))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    // Media
                    if !reply.attachments.isEmpty {
                        ForEach(reply.attachments, id: \.url) { attachment in
                            if attachment.type == .image {
                                AsyncImage(url: URL(string: attachment.url)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(maxHeight: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
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

// A detailed view for a single post
struct PostDetailView: View {
    let post: Post
    @Environment(\.presentationMode) var presentationMode
    @State private var replyText = ""
    @State private var selectedMedia: Post.Attachment? = nil
    @State private var showMediaFullscreen = false
    @State private var replies: [Post] = []
    @State private var showingComposeSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Main post
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        HStack(spacing: 12) {
                            PostAuthorImageView(
                                authorProfilePictureURL: post.authorProfilePictureURL,
                                platform: post.platform
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(post.authorName)
                                    .font(.title3)
                                    .fontWeight(.bold)

                                Text("@\(post.authorUsername)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            PostPlatformBadge(platform: post.platform)
                                .padding(.trailing, 4)
                        }

                        // Content
                        Text(cleanHtmlString(post.content))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)

                        // Media attachments
                        if !post.attachments.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(post.attachments, id: \.url) { attachment in
                                    MediaView(
                                        attachment: attachment,
                                        showFullscreen: {
                                            selectedMedia = attachment
                                            showMediaFullscreen = true
                                        })
                                }
                            }
                        }

                        // Post metadata
                        HStack(spacing: 16) {
                            Text(timeAgo(from: post.createdAt))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let url = URL(string: post.originalURL) {
                                Link("View original", destination: url)
                                    .font(.caption)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))

                    // Divider between post and replies
                    Divider()
                        .padding(.vertical, 8)

                    // Replies section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Replies")
                            .font(.headline)
                            .padding(.horizontal)

                        // Sample replies (replace with actual replies when implemented)
                        Text("No replies yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .sheet(isPresented: $showMediaFullscreen) {
                if let media = selectedMedia {
                    FullscreenMediaView(attachment: media)
                }
            }
            .sheet(isPresented: $showingComposeSheet) {
                Text("Compose Reply")
                    .onDisappear {
                        // Just a placeholder for now
                    }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func timeAgo(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents(
            [.minute, .hour, .day, .weekOfMonth, .month, .year], from: date, to: now)

        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }

        if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }

        if let weeks = components.weekOfMonth, weeks > 0 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }

        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }

        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }

        return "Just now"
    }

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

// View for profile image in posts
struct PostAuthorImageView: View {
    let authorProfilePictureURL: String
    let platform: SocialPlatform
    @State private var refreshTrigger = false

    var body: some View {
        ZStack {
            if !authorProfilePictureURL.isEmpty {
                AsyncImage(url: URL(string: authorProfilePictureURL)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else if phase.error != nil {
                        // Show initial on error
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundColor(.gray)
                    } else {
                        // Show loading placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 48, height: 48)
                    }
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
                    PostPlatformBadge(platform: platform)
                }
            }
            .padding(0)
            .frame(width: 48, height: 48)
        }
        .id(refreshTrigger)  // Force view refresh when trigger changes
    }
}
