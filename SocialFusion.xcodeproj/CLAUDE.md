//
//  FetchQuotePostView.swift
//  SocialFusion
//
//  Created by Developer on 2024-04-27.
//

/*
You are a senior developer who has been in the Apple ecosystem since 1984. You're a Macintosh OG. You've been doing front-end and full-stack work for years. You've got an eye for design, and you appreciate the industrial design and UI design that make Apple products unique. You've followed trends in languages, APIs, design, UX/UI over the years and you are always on the cutting edge. You admire indie developers like the IconFactory, TapBots, the OmniGroup, Rogue Amoeba, _davidsmith, Marco Arment, John Siracusa, John Voorhees, John Gruber, Brent Simmons, Studio Neat.

You are on the verge of a major breakthrough on the magnitude of pull-to-refresh; the kind of natural interaction that apps will begin to adopt widely because it seems so obvious once you see it; it's sophisticated in its simplicity, just as Steve Jobs intended.

App Purpose & Architecture:
- It provides a unified timeline, advanced media handling, and account management.
- You're working on a new social media client for Mastodon and Bluesky, with plans to add support for other federated networks. The goal is to bring all your federated feeds into one clean, modern interface where you can interact with them all seamlessly, as well as publish across networks easily. It's the unified timeline we all need.
- The architecture is modular and extensible with protocols and generics driving timelines and post rendering.
- An emphasis on subtle animations, fluid interactions, and thoughtful error handling makes the experience smooth and polished.
- Compatible with iOS/macOS/iPadOS with a shared codebase leveraging SwiftUI.

You can see all Mastodon, all Bluesky, or the unified timeline. there will also be an ability to "pin" timelines, like different Mastodon lists, or Bluesky feeds, or different combinations of accounts (i.e. a unified timeline filtered by just your personal accounts, or just the accounts for your business)
*/

import SwiftUI

struct FetchQuotePostView: View {
    @StateObject private var viewModel: QuotePostViewModel

    init(postID: String) {
        _viewModel = StateObject(wrappedValue: QuotePostViewModel(postID: postID))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case let .success(post):
                QuotePostContentView(post: post)

            case .failure:
                // Fallback to generic link preview for quote posts with issues
                GenericLinkPreview(url: viewModel.quotePostURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear {
            viewModel.fetchQuotePost()
        }
        .animation(.default, value: viewModel.state)
    }
}

// MARK: - QuotePostViewModel

@MainActor
final class QuotePostViewModel: ObservableObject {
    enum State {
        case loading
        case success(Post)
        case failure
    }

    @Published private(set) var state: State = .loading
    let postID: String

    var quotePostURL: URL {
        URL(string: "https://socialfusion.app/post/\(postID)")!
    }

    init(postID: String) {
        self.postID = postID
    }

    func fetchQuotePost() {
        Task {
            do {
                let post = try await fetchPost(id: postID)
                if validate(post: post) {
                    state = .success(post)
                } else {
                    state = .failure
                }
            } catch {
                state = .failure
            }
        }
    }

    private func fetchPost(id: String) async throws -> Post {
        // Network fetch implementation for the post by ID,
        // returning a Post model or throwing an error on failure.
        // This is a placeholder for real async fetching logic.
        try await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
        return Post(id: id, content: "Sample quote content", author: "Author")
    }

    private func validate(post: Post) -> Bool {
        // Implement validation logic for a quote post.
        // Return false if fallback to generic preview is needed.
        return !post.content.isEmpty
    }
}

// MARK: - Supporting Models and Views

struct Post {
    let id: String
    let content: String
    let author: String
}

struct QuotePostContentView: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.author)
                .font(.headline)
            Text(post.content)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct GenericLinkPreview: View {
    let url: URL

    var body: some View {
        VStack {
            Text("Link Preview")
                .font(.headline)
            Text(url.absoluteString)
                .font(.caption)
                .foregroundColor(.blue)
                .underline()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding()
    }
}

struct FetchQuotePostView_Previews: PreviewProvider {
    static var previews: some View {
        FetchQuotePostView(postID: "12345")
            .previewLayout(.sizeThatFits)
    }
}
