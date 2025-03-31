import SwiftUI

struct PostCardView: View {
    let post: Post
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with author info and platform indicator
            HStack {
                // Author avatar
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
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(post.author.displayName)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        // Platform indicator
                        HStack(spacing: 4) {
                            Image(systemName: post.platform.icon)
                                .font(.system(size: 12))
                            Text(post.platform.rawValue)
                                .font(.caption)
                        }
                        .foregroundColor(Color(post.platform.color))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(post.platform.color).opacity(0.1))
                        )
                    }
                    
                    Text("@\(post.author.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Post time
                Text(timeAgo(from: post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Post content
            Text(post.content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            // Media attachments if any
            if !post.mediaAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.mediaAttachments) { attachment in
                            if attachment.type == .image || attachment.type == .gifv {
                                AsyncImage(url: attachment.url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                }
                                .frame(width: 200, height: 150)
                                .cornerRadius(8)
                            } else if attachment.type == .video {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.8))
                                        .frame(width: 200, height: 150)
                                        .cornerRadius(8)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                }
            }
            
            // Action buttons
            HStack(spacing: 24) {
                // Reply
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                        Text("\(post.replyCount)")
                    }
                    .foregroundColor(.secondary)
                }
                
                // Repost
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isReposted ? "arrow.2.squarepath.fill" : "arrow.2.squarepath")
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
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    // Helper function to format dates as relative time
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PostCardView(post: Post.samplePosts[0])
            PostCardView(post: Post.samplePosts[1])
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}