import Foundation
import SwiftUI

/// A test playground to verify link detection and preview functionality
struct LinkTestPlayground: View {
    @State private var testResults: [String] = []

    private let testTexts = [
        "Check out this article: https://www.example.com/article",
        "Visit https://apple.com for more info",
        "Here's a link to https://github.com/socialfusion",
        "<p>This is <a href=\"https://www.mastodon.social\">a mastodon link</a> in HTML</p>",
        "Multiple links: https://www.google.com and https://www.apple.com",
        "YouTube video: https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    ]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Link Detection Test")
                    .font(.title)
                    .padding()

                Button("Run Link Tests") {
                    runTests()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(testResults, id: \.self) { result in
                            Text(result)
                                .font(.caption)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            print("🔍 LinkTestPlayground appeared - running tests")
            runTests()
        }
    }

    private func runTests() {
        testResults.removeAll()

        print("🔍 Starting link detection tests...")

        for (index, text) in testTexts.enumerated() {
            print("🔍 Test \(index + 1): '\(text)'")

            let links = URLService.shared.extractLinks(from: text)
            let resultText =
                "Test \(index + 1): Found \(links.count) links in: '\(text.prefix(50))...'"
            testResults.append(resultText)

            for link in links {
                let linkResult = "  → \(link.absoluteString)"
                testResults.append(linkResult)
                print("🔍   Found link: \(link.absoluteString)")
            }
        }

        print("🔍 Link detection tests completed")
    }
}

// Test with actual Post content
struct PostLinkTestView: View {
    private let samplePosts = [
        Post(
            id: "test1",
            authorUsername: "testuser",
            authorDisplayName: "Test User",
            authorAvatarURL: "",
            content: "Check out this great article: https://www.apple.com/news",
            createdAt: Date(),
            attachments: [],
            repostCount: 0,
            likeCount: 0,
            replyCount: 0,
            isReposted: false,
            isLiked: false,
            mentions: [],
            tags: [],
            platform: .bluesky,
            originalURL: "https://test.com/post1"
        ),
        Post(
            id: "test2",
            authorUsername: "testuser2",
            authorDisplayName: "Test User 2",
            authorAvatarURL: "",
            content: "Multiple links here: https://github.com and https://swift.org",
            createdAt: Date(),
            attachments: [],
            repostCount: 0,
            likeCount: 0,
            replyCount: 0,
            isReposted: false,
            isLiked: false,
            mentions: [],
            tags: [],
            platform: .bluesky,
            originalURL: "https://test.com/post2"
        ),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Post Link Preview Test")
                        .font(.title)
                        .padding()

                    ForEach(samplePosts, id: \.id) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("@\(post.authorUsername)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            post.contentView(
                                lineLimit: nil,
                                showLinkPreview: true,
                                font: .body
                            )
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
    }
}

struct TestPlayground_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LinkTestPlayground()
            PostLinkTestView()
        }
    }
}
