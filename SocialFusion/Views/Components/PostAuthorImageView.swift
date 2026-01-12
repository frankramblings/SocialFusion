import SwiftUI

/// Avatar view with platform indicator badge using SVG logos
struct PostAuthorImageView: View {
    var platform: SocialPlatform
    var size: CGFloat = 44
    var authorName: String = ""

    // Capture stable values at init time to prevent AsyncImage cancellation
    private let stableImageURL: URL?
    private let debugDescription: String
    private let initials: String

    init(
        authorProfilePictureURL: String, platform: SocialPlatform, size: CGFloat = 44,
        authorName: String = ""
    ) {
        self.stableImageURL = URL(string: authorProfilePictureURL)
        self.platform = platform
        self.size = size
        self.authorName = authorName
        self.debugDescription = "\(platform.rawValue):\(authorProfilePictureURL.suffix(20))"

        // Generate initials from author name for fallback
        self.initials = Self.generateInitials(from: authorName)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Overlay actual profile image when available
            if let stableImageURL = stableImageURL {
                CachedAsyncImage(url: stableImageURL, priority: .high) { image in
                    // Render image on neutral backing to prevent bleed-through for transparent PNGs
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemFill))
                        
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .transition(.opacity)
                    }
                    .frame(width: size, height: size)
                } placeholder: {
                    // Show initials + spinner while loading or on failure
                    ZStack {
                        initialsBackground
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                        
                        ProgressView()
                            .scaleEffect(0.6)
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white.opacity(0.8)))
                    }
                }
            } else {
                // Fallback for missing URL
                initialsBackground
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }

            // Border overlay
            Circle()
                .stroke(Color(.systemBackground), lineWidth: 1)
                .frame(width: size, height: size)

            // Platform indicator badge with SVG logo and full Liquid Glass
            PlatformLogoBadge(
                platform: platform,
                size: max(18, size * 0.38),  // Increased size for better visibility (10% larger)
                shadowEnabled: true
            )
            .offset(x: 2, y: 2)  // Small offset to position badge properly
        }
    }

    // Computed property for initials background (like Twitter, Instagram, etc.)
    private var initialsBackground: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(
                            hue: Double(abs(authorName.hashValue) % 360) / 360.0, saturation: 0.6,
                            brightness: 0.8),
                        Color(
                            hue: Double(abs(authorName.hashValue) % 360) / 360.0, saturation: 0.8,
                            brightness: 0.6),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Group {
                    if !initials.isEmpty {
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: size * 0.4))
                    }
                }
            )
    }

    // Generate initials from a name (like best-in-class apps)
    static func generateInitials(from name: String) -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return "" }

        let components = cleanName.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        if components.count >= 2 {
            // First and last name
            let first = String(components.first?.first ?? Character(""))
            let last = String(components.last?.first ?? Character(""))
            return (first + last).uppercased()
        } else if let firstComponent = components.first, !firstComponent.isEmpty {
            // Single name - take first two characters if possible
            let chars = Array(firstComponent)
            if chars.count >= 2 {
                return String(chars[0...1]).uppercased()
            } else {
                return String(chars[0]).uppercased()
            }
        }

        return ""
    }
}

#Preview("Avatar Previews") {
    VStack(spacing: 20) {
        // Different sizes
        HStack(spacing: 16) {
            VStack {
                Text("32pt")
                    .font(.caption2)
                PostAuthorImageView(
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    platform: .bluesky,
                    size: 32,
                    authorName: "John Doe"
                )
            }

            VStack {
                Text("44pt (default)")
                    .font(.caption2)
                PostAuthorImageView(
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    platform: .mastodon,
                    authorName: "Jane Smith"
                )
            }

            VStack {
                Text("60pt")
                    .font(.caption2)
                PostAuthorImageView(
                    authorProfilePictureURL: "https://example.com/avatar.jpg",
                    platform: .bluesky,
                    size: 60,
                    authorName: "Alice Johnson"
                )
            }
        }

        // Fallback states (no image URL)
        HStack(spacing: 16) {
            PostAuthorImageView(
                authorProfilePictureURL: "",
                platform: .bluesky,
                authorName: "No Image User"
            )

            PostAuthorImageView(
                authorProfilePictureURL: "",
                platform: .mastodon,
                authorName: "Test"
            )

            PostAuthorImageView(
                authorProfilePictureURL: "",
                platform: .bluesky,
                authorName: ""  // No name either
            )
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
