import SwiftUI

/// A compact view of a quoted post - styled like ParentPostPreview
public struct QuotedPostView: View {
    public let post: Post
    public var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var navigationEnvironment: PostNavigationEnvironment

    // Maximum characters before content is trimmed
    private let maxCharacters = 300

    public init(post: Post, onTap: (() -> Void)? = nil) {
        self.post = post
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author row
            authorHeader

            // Post content
            postContent

            // Attachments (if any)
            if !post.attachments.isEmpty {
                postAttachment
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticEngine.tap.trigger()
            onTap?()
        }
    }

    // MARK: - View Components

    private var authorHeader: some View {
        // Wrap navigation with tap haptic so the avatar/name/handle
        // buttons feel responsive — same shape as PostAuthorView's
        // onAuthorTapWithHaptic (9270925). Only one of the three
        // buttons can fire per tap so no double-haptic risk.
        let navigateWithHaptic: () -> Void = {
            HapticEngine.tap.trigger()
            navigationEnvironment.navigateToUser(from: post)
        }

        return HStack(spacing: 8) {
            // Author avatar with platform indicator
            Button(action: navigateWithHaptic) {
                ZStack(alignment: .bottomTrailing) {
                    let stableImageURL = URL(string: post.authorProfilePictureURL)
                    let quoteInitial = String((post.authorName.isEmpty ? post.authorUsername : post.authorName).prefix(1)).uppercased()
                    CachedAsyncImage(url: stableImageURL, priority: .high) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                            .overlay(
                                Text(quoteInitial.isEmpty ? "?" : quoteInitial)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(Color(.systemGray))
                            )
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .id(stableImageURL?.absoluteString ?? "no-url")

                    PlatformDot(
                        platform: post.platform, size: 14, useLogo: true  // Increased from 12 to 14 for better visibility
                    )
                    .background(
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    )
                    .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Author info
            VStack(alignment: .leading, spacing: 1) {
                Button(action: navigateWithHaptic) {
                    EmojiDisplayNameText(
                        post.authorName,
                        emojiMap: post.authorEmojiMap,
                        font: .subheadline,
                        fontWeight: .semibold,
                        foregroundColor: .primary,
                        lineLimit: 1
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: navigateWithHaptic) {
                    Text("@\(post.authorUsername)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            // Time ago
            RelativeTimeView(date: post.createdAt)
        }
    }

    private var postContent: some View {
        let lineLimit = post.content.count > maxCharacters ? 4 : nil
        return post.contentView(
            lineLimit: lineLimit, showLinkPreview: true, allowTruncation: false
        )
        .font(.callout)
        .padding(.horizontal, 4)
        // Prevent nested quotes in quote cards
        .environment(\.preventNestedQuotes, true)
    }

    private var postAttachment: some View {
        UnifiedMediaGridView(
            attachments: post.attachments,
            maxHeight: 220
        )
        .clipShape(
            RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
        )
        .padding(.top, 4)
    }

    private var backgroundStyle: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.15)
                    : Color.black.opacity(0.1),
                lineWidth: 0.5
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.02)
            : Color.black.opacity(0.05)
    }
}

/// Fetches and displays a quoted post from a URL with improved stability
struct FetchQuotePostView: View {
    let url: URL
    var onQuotePostTap: ((Post) -> Void)? = nil
    var fallbackPost: Post? = nil
    @State private var quotedPost: Post? = nil
    @State private var isLoading = true
    @State private var error: Error? = nil
    @State private var retryCount = 0
    @State private var fetchTask: Task<Void, Never>?
    @State private var terminalReason: QuotePostUnavailableView.Reason? = nil
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var navigationEnvironment: PostNavigationEnvironment
    @EnvironmentObject private var fusedMomentStore: FusedMomentStore
    @Environment(\.colorScheme) private var colorScheme

    private let maxRetries = 2

    /// Once a URL is resolved to a Post, keep it. The dominant cause of
    /// "feed shifts while I scroll" is a quote cell above the viewport
    /// transitioning from skeleton → loaded after its fetch completes.
    /// Caching means the second (and Nth) time you scroll past a known
    /// quote, the cell lands at its final size on the first frame and
    /// nothing below it shifts. Ivory et al. avoid the same jump by
    /// shipping embed data inline; we don't always have that for
    /// Mastodon, so cache-on-resolve is the moral equivalent.
    @MainActor private static var resolvedPostCache: [URL: Post] = [:]
    @MainActor private static var negativeCache: Set<URL> = []  // URLs that resolved to nothing — don't keep retrying

    private var platform: SocialPlatform {
        let urlString = url.absoluteString.lowercased()
        // Check for Bluesky URLs (various formats)
        if urlString.contains("bsky.app") || 
           urlString.contains("bsky.social") ||
           url.scheme == "at" ||
           urlString.contains("at://") {
            return .bluesky
        }
        // Default to Mastodon for other social media URLs
        return .mastodon
    }

    var body: some View {
        Group {
            if let post = quotedPost, hasMeaningfulContent(post) {
                QuotedPostView(post: post) {
                    DebugLog.verbose("🔗 [FetchQuotePostView] Quote post tapped: \(post.id)")
                    handleQuoteTap(for: post)
                }
            } else if let fallbackPost = fallbackPost, hasMeaningfulContent(fallbackPost) {
                // Show embedded quote data while we fetch full details/attachments.
                QuotedPostView(post: fallbackPost) {
                    handleQuoteTap(for: fallbackPost)
                }
            } else if isLoading {
                LoadingQuoteView(platform: platform)
            } else if error != nil && retryCount <= maxRetries {
                // Show error state with retry option (only if we haven't exceeded max retries)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange.gradient)
                            .symbolRenderingMode(.hierarchical)
                        Text("Couldn't load quoted post")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary.opacity(0.78))
                        Spacer()
                        Button {
                            HapticEngine.tap.trigger()
                            retryCount = 0  // Reset retry count for manual retry
                            Task {
                                await fetchPost()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                Text("Retry")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else if let reason = terminalReason {
                // Retries exhausted: render the unavailable placeholder
                // with a classified reason so the user knows this *was*
                // a quoted post that couldn't load — rather than a generic
                // link card that pretends nothing was attempted.
                QuotePostUnavailableView(
                    reason: reason,
                    originalURL: url,
                    platform: platform
                )
            } else {
                // Fallback to the stabilized link preview when the
                // social-media post can't be fetched as a quote.
                // StabilizedLinkPreview reserves identical heights
                // across loading / loaded / fallback states, so the
                // quote-post → link-card transition no longer pushes
                // posts below it down the feed.
                StabilizedLinkPreview(url: url)
            }
        }
        .onAppear {
            // Cache hit: the URL was resolved earlier in this session.
            // Render the loaded view on the very first frame so the cell
            // lands at its final size and nothing below it shifts when
            // the (otherwise-needed) fetch would have completed.
            if let cached = Self.resolvedPostCache[url] {
                if quotedPost == nil { quotedPost = cached }
                if isLoading { isLoading = false }
                return
            }
            // Negative cache: we tried this URL before and it didn't
            // resolve to a quote. Skip the fetch; the body's `else`
            // branch will render LinkPreview at its stable size.
            if Self.negativeCache.contains(url) {
                if isLoading { isLoading = false }
                return
            }
            // Only start a fetch if we don't already have data and there
            // isn't one in flight. This prevents duplicate requests when
            // the cell is briefly recycled by LazyVStack.
            guard quotedPost == nil, fetchTask == nil else { return }
            DebugLog.verbose("🔗 [FetchQuotePostView] Scheduling fetch for URL: \(url)")
            fetchTask = Task {
                // Visibility-confirmation delay. LazyVStack instantiates
                // cells in a buffer outside the visible viewport — a fast
                // scroll past a quote cell will fire onAppear briefly,
                // then onDisappear. Wait ~350ms so we only pay the network
                // cost (and risk the size-jump on result) for cells the
                // user actually dwells on. Cancelled by onDisappear if
                // the cell scrolls off before the timer fires.
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await fetchPost()
                await MainActor.run { fetchTask = nil }
            }
        }
        .onDisappear {
            // CRITICAL: cancel any in-flight fetch when the cell scrolls
            // off-screen. Otherwise the response can arrive *after* the
            // user has scrolled past, setting quotedPost on an out-of-view
            // cell — which then expands by ~220pt when its UnifiedMediaGridView
            // appears, pushing the user's current viewport content downward.
            // This is the dominant cause of the 'feed jumps as I scroll' bug.
            fetchTask?.cancel()
            fetchTask = nil
        }
    }

    private func handleQuoteTap(for post: Post) {
        if let onQuotePostTap = onQuotePostTap {
            DebugLog.verbose("🔗 [FetchQuotePostView] Using provided onQuotePostTap callback")
            onQuotePostTap(post)
        } else {
            // Fused-aware: if this quoted post participates in a known
            // FusedMoment, open the unified conversation view rather
            // than the per-network detail. Same rule as ProfileView and
            // SearchView (3828b0c) — closes the last surface where a
            // tap on a Fused post could land on the per-network detail.
            DebugLog.verbose("🔗 [FetchQuotePostView] Using navigationEnvironment.navigateToPostFusedAware")
            navigationEnvironment.navigateToPostFusedAware(post, fusedMomentStore: fusedMomentStore)
        }
    }

    // Helper to determine if a post has meaningful content
    private func hasMeaningfulContent(_ post: Post) -> Bool {
        let hasText = !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = !post.attachments.isEmpty
        let hasAuthor = !post.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let isValid = hasText || hasMedia || hasAuthor
        
        if !isValid {
            DebugLog.verbose("🔗 [FetchQuotePostView] Post has no meaningful content - text: \(hasText), media: \(hasMedia), author: \(hasAuthor)")
        } else {
            DebugLog.verbose("🔗 [FetchQuotePostView] Post has meaningful content - text: \(hasText), media: \(hasMedia) (\(post.attachments.count) attachments), author: \(hasAuthor)")
        }
        
        return isValid
    }

    /// Maps a quote-fetch error to a user-facing reason. Conservative: when
    /// the error doesn't fit a known shape, returns `.unknown` (which the
    /// view renders with the same "no longer available" copy as `.deleted`
    /// — both are accurate at the end of a retry cycle when the post still
    /// isn't reachable).
    static func classify(error: Error?) -> QuotePostUnavailableView.Reason {
        guard let error = error else { return .unknown }
        let nsError = error as NSError

        // URLError → almost always a transient connectivity problem; the
        // user CAN open the original URL in their browser.
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return .network
            default:
                return .network
            }
        }

        // Decoding / JSON errors → server replied with something we
        // couldn't parse. Distinct from "post is gone" — show malformed.
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 3840 {
            return .malformed
        }
        if error is DecodingError {
            return .malformed
        }

        // HTTP status codes if surfaced via NSError.code (some services do).
        switch nsError.code {
        case 404, 410:
            return .deleted
        case 401, 403:
            return .blocked
        default:
            // Inspect localized description for HTTP hints (some services
            // bury the status code inside the message rather than .code).
            let desc = nsError.localizedDescription.lowercased()
            if desc.contains("404") || desc.contains("not found") || desc.contains("gone") {
                return .deleted
            }
            if desc.contains("401") || desc.contains("403") || desc.contains("forbidden") || desc.contains("unauthorized") {
                return .blocked
            }
            return .unknown
        }
    }

    private func fetchPost() async {
        guard retryCount <= maxRetries else {
            DebugLog.verbose("🔗 [FetchQuotePostView] Max retries exceeded for URL: \(url)")
            isLoading = false
            error = NSError(
                domain: "FetchQuotePostView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Maximum retries exceeded"]
            )
            return
        }

        DebugLog.verbose("🔗 [FetchQuotePostView] Fetching post for URL: \(url) (attempt \(retryCount + 1))")

        isLoading = true
        error = nil

        do {
            let post: Post?

            // Determine platform based on URL
            let urlString = url.absoluteString.lowercased()
            let isBluesky = urlString.contains("bsky.app") || 
                           urlString.contains("bsky.social") ||
                           url.scheme == "at" ||
                           urlString.contains("at://")
            
            if isBluesky {
                post = try await fetchBlueskyPost()
            } else if URLService.shared.isFediversePostURL(url) {
                // Use URLService pattern-based detection for all fediverse platforms
                // This covers Mastodon, Pleroma, Akkoma, Misskey, Pixelfed, GoToSocial, etc.
                post = try await fetchMastodonPost()
            } else {
                DebugLog.verbose("🔗 [FetchQuotePostView] Unsupported platform for URL: \(url)")
                throw NSError(
                    domain: "FetchQuotePostView",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported platform for URL: \(url.absoluteString)"]
                )
            }

            // Bail if the cell has scrolled off-screen and the task was
            // cancelled during the network round-trip. Setting state here
            // would grow a now-invisible cell and shove the user's viewport
            // content down.
            guard !Task.isCancelled else {
                DebugLog.verbose("🔗 [FetchQuotePostView] Task cancelled after fetch; dropping result for \(url)")
                return
            }

            if let post = post {
                // Validate that the post has meaningful content before setting it
                if hasMeaningfulContent(post) {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        Self.resolvedPostCache[url] = post
                        self.quotedPost = post
                        self.isLoading = false
                        self.error = nil
                    }
                } else {
                    // Post was fetched but has no meaningful content - fallback to LinkPreview
                    // Don't throw error, just don't set the quotedPost
                    DebugLog.verbose("🔗 [FetchQuotePostView] Post fetched but has no meaningful content, falling back to LinkPreview: \(url)")
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        Self.negativeCache.insert(url)
                        self.isLoading = false
                        self.error = nil
                        // Leave quotedPost as nil so it falls through to LinkPreview
                    }
                }
            } else {
                // Post fetch returned nil - fallback to LinkPreview instead of error
                // This ensures the post still displays even if quote fetch fails
                DebugLog.verbose("🔗 [FetchQuotePostView] Post fetch returned nil, falling back to LinkPreview: \(url)")
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    Self.negativeCache.insert(url)
                    self.isLoading = false
                    self.error = nil
                    // Leave quotedPost as nil so it falls through to LinkPreview
                }
            }

        } catch {
            // Distinguish cancellation from real errors. Cancellation means
            // the cell scrolled off-screen — silently bail without retrying
            // or surfacing an error UI.
            if Task.isCancelled || error is CancellationError {
                DebugLog.verbose("🔗 [FetchQuotePostView] Fetch cancelled (cell off-screen) for \(url)")
                return
            }

            DebugLog.verbose("🔗 [FetchQuotePostView] Error fetching post: \(error)")
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.retryCount += 1
                self.isLoading = false
                self.error = error
            }

            // Retry with exponential backoff
            if retryCount <= maxRetries {
                let delay = min(pow(2.0, Double(retryCount)), 30.0)
                DebugLog.verbose("🔗 [FetchQuotePostView] Retrying in \(delay) seconds...")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await fetchPost()
            } else {
                // Retries exhausted. Classify the final error so the
                // placeholder can show an honest reason ("deleted",
                // "blocked", "network", etc.) instead of falling through
                // to LinkPreview, which strips the quoted-post framing.
                let classified = Self.classify(error: error)
                DebugLog.verbose("🔗 [FetchQuotePostView] Max retries exceeded, classified as \(classified)")
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    Self.negativeCache.insert(url)
                    self.isLoading = false
                    self.error = nil
                    self.terminalReason = classified
                }
            }
        }
    }

    private func fetchBlueskyPost() async throws -> Post? {
        // The Bluesky API requires a full AT Protocol URI for getPostThread
        // We need to construct it from the URL

        // Handle AT Protocol URIs directly (at://did:plc:xxx/app.bsky.feed.post/xxx)
        if url.scheme == "at" {
            let atUri = url.absoluteString
            DebugLog.verbose("🔗 [FetchQuotePostView] Using AT URI directly: \(atUri)")
            return try await serviceManager.fetchBlueskyPostByID(atUri)
        }

        let components = url.path.split(separator: "/").map(String.init)

        // Bluesky URLs can be in different formats:
        // - https://bsky.app/profile/handle/post/postid (4+ components: profile, handle, post, postid)
        // - https://handle.bsky.social/post/postid (2 components: post, postid)

        var handle: String?
        var postID: String?

        // Format: /profile/handle/post/postid
        if let profileIndex = components.firstIndex(where: { $0 == "profile" }),
           profileIndex + 1 < components.count,
           let postIndex = components.firstIndex(where: { $0 == "post" }),
           postIndex + 1 < components.count {
            handle = components[profileIndex + 1]
            postID = components[postIndex + 1]
        }
        // Format: handle.bsky.social/post/postid (handle is in the host)
        else if let host = url.host?.lowercased(), host.contains("bsky.social") {
            // Extract handle from host (e.g., "handle.bsky.social" -> "handle")
            let hostParts = host.split(separator: ".")
            if hostParts.count >= 3 && hostParts[1] == "bsky" {
                handle = String(hostParts[0])
            }
            if let postIndex = components.firstIndex(where: { $0 == "post" }),
               postIndex + 1 < components.count {
                postID = components[postIndex + 1]
            }
        }
        // Fallback: try to get post ID from path
        else if let postIndex = components.firstIndex(where: { $0 == "post" }),
                postIndex + 1 < components.count {
            postID = components[postIndex + 1]
            // Try to get handle from URL components
            if postIndex > 0 {
                handle = components[postIndex - 1]
            }
        }

        guard let postID = postID, !postID.isEmpty else {
            DebugLog.verbose("🔗 [FetchQuotePostView] Could not extract post ID from URL: \(url)")
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Bluesky post URL format: \(url.absoluteString)"]
            )
        }

        // If we have a handle, we can construct a proper AT URI by first resolving the handle to a DID
        // For now, we'll use the handle-based URI which the API should accept
        // The API needs a full at:// URI, so we need to resolve the handle to a DID first
        if let handle = handle {
            DebugLog.verbose("🔗 [FetchQuotePostView] Resolving handle '\(handle)' to construct AT URI for post: \(postID)")
            // Construct a handle-based URI - the API will resolve it
            // Format: at://handle/app.bsky.feed.post/postid
            let atUri = "at://\(handle)/app.bsky.feed.post/\(postID)"
            DebugLog.verbose("🔗 [FetchQuotePostView] Constructed AT URI: \(atUri)")
            return try await serviceManager.fetchBlueskyPostByID(atUri)
        } else {
            // No handle available, cannot construct proper AT URI
            DebugLog.verbose("🔗 [FetchQuotePostView] No handle found in URL, cannot construct AT URI: \(url)")
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot construct AT URI without handle: \(url.absoluteString)"]
            )
        }
    }

    private func fetchMastodonPost() async throws -> Post? {
        guard let account = serviceManager.accounts.first(where: { $0.platform == .mastodon })
        else {
            throw NSError(
                domain: "FetchQuotePostView",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No Mastodon account available"]
            )
        }

        // CRITICAL: Use the Mastodon search API to resolve remote posts
        // The search API with resolve=true will federate the post to the user's instance
        // This is the correct way to fetch posts from other instances
        DebugLog.verbose("🔗 [FetchQuotePostView] Using search API to resolve remote post URL: \(url)")
        
        do {
            let searchResult = try await serviceManager.searchMastodonWithPosts(
                query: url.absoluteString,
                account: account,
                type: "statuses",
                limit: 1
            )
            
            if let firstPost = searchResult.first {
                DebugLog.verbose("🔗 [FetchQuotePostView] Successfully resolved remote post: \(firstPost.id)")
                return firstPost
            } else {
                DebugLog.verbose("🔗 [FetchQuotePostView] Search returned no results for URL: \(url)")
                return nil
            }
        } catch {
            DebugLog.verbose("🔗 [FetchQuotePostView] Search API failed: \(error), falling back to direct fetch")
            
            // Fallback: try direct fetch if search fails (for local posts)
            return try await fetchMastodonPostDirect(account: account)
        }
    }
    
    /// Direct fetch fallback for local posts (when search API fails)
    private func fetchMastodonPostDirect(account: SocialAccount) async throws -> Post? {
        let path = url.path
        let pathLowercased = path.lowercased()
        let components = path.split(separator: "/").map(String.init)

        guard components.count >= 1 else {
            DebugLog.verbose("🔗 [FetchQuotePostView] Invalid fediverse URL format: \(url)")
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid fediverse post URL format: \(url.absoluteString)"]
            )
        }

        // Extract post ID based on various fediverse URL patterns
        var postID: String?

        // Pattern 1: /@username/postID (Mastodon standard)
        if path.contains("/@") && components.count >= 2 {
            let lastComponent = components.last!
            if lastComponent.allSatisfy({ $0.isNumber }) {
                postID = lastComponent
            }
        }

        // Pattern 2: /users/username/statuses/postID (ActivityPub canonical)
        if postID == nil && pathLowercased.contains("/statuses/") {
            if let statusesIdx = components.firstIndex(where: { $0.lowercased() == "statuses" }),
               statusesIdx + 1 < components.count {
                postID = components[statusesIdx + 1]
            }
        }

        // Pattern 3: /notes/noteID (Misskey/Firefish/Calckey)
        if postID == nil && pathLowercased.contains("/notes/") {
            if let idx = components.firstIndex(where: { $0.lowercased() == "notes" }),
               idx + 1 < components.count {
                postID = components[idx + 1]
            }
        }

        // Pattern 4: /notice/noticeID (Pleroma/Akkoma)
        if postID == nil && pathLowercased.contains("/notice/") {
            if let idx = components.firstIndex(where: { $0.lowercased() == "notice" }),
               idx + 1 < components.count {
                postID = components[idx + 1]
            }
        }

        // Pattern 5: /objects/objectID (Pleroma/Akkoma ActivityPub)
        if postID == nil && pathLowercased.contains("/objects/") {
            if let idx = components.firstIndex(where: { $0.lowercased() == "objects" }),
               idx + 1 < components.count {
                postID = components[idx + 1]
            }
        }

        // Pattern 6: /p/username/postID (Pixelfed)
        if postID == nil && pathLowercased.contains("/p/") && components.count >= 3 {
            if let pIdx = components.firstIndex(where: { $0.lowercased() == "p" }),
               pIdx + 2 < components.count {
                postID = components[pIdx + 2]
            }
        }

        // Pattern 7: /post/postID (Lemmy)
        if postID == nil && pathLowercased.hasPrefix("/post/") && components.count >= 2 {
            postID = components[1]
        }

        // Pattern 8: /display/GUID (Friendica)
        if postID == nil && pathLowercased.hasPrefix("/display/") && components.count >= 2 {
            postID = components[1]
        }

        // Fallback: use the last component
        if postID == nil && !components.isEmpty {
            postID = components.last
        }

        guard let postID = postID, !postID.isEmpty else {
            DebugLog.verbose("🔗 [FetchQuotePostView] Could not extract post ID from URL: \(url)")
            throw NSError(
                domain: "FetchQuotePostView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not extract post ID from URL: \(url.absoluteString)"]
            )
        }

        DebugLog.verbose("🔗 [FetchQuotePostView] Extracted fediverse post ID: \(postID) from URL: \(url)")
        return try await serviceManager.fetchMastodonStatus(id: postID, account: account)
    }
}

/// Improved loading view for quote posts
struct LoadingQuoteView: View {
    let platform: SocialPlatform
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // System grays adapt cleanly to light/dark mode. Color.gray
        // is a fixed device color and reads as brown-tinted against
        // dark backgrounds — the same fix the codebase already
        // applied to SkeletonPostCard, LinkPreview, and ProfileView.
        let heavyFill = Color(.systemGray4)
        let lightFill = Color(.systemGray5)

        return VStack(alignment: .leading, spacing: 6) {
            // Author placeholder
            HStack(spacing: 8) {
                Circle()
                    .fill(heavyFill)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .fill(platformColor.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .offset(x: 10, y: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(heavyFill)
                        .frame(width: 80, height: 12)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(lightFill)
                        .frame(width: 60, height: 10)
                        .cornerRadius(4)
                }

                Spacer()

                Rectangle()
                    .fill(lightFill)
                    .frame(width: 40, height: 10)
                    .cornerRadius(4)
            }

            // Content placeholder — 4 lines of skeleton so the reserved
            // space approximates a typical quoted post body (~3-4 lines).
            // Loaded posts can still be taller (e.g. with attachments) or
            // shorter (single-line replies), but landing closer to the
            // median minimizes the average jump when the cell transitions
            // from skeleton → loaded content above the viewport.
            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(lightFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .cornerRadius(4)

                Rectangle()
                    .fill(lightFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .cornerRadius(4)

                Rectangle()
                    .fill(lightFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .cornerRadius(4)

                Rectangle()
                    .fill(lightFill)
                    .frame(maxWidth: 200)
                    .frame(height: 12)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(borderOverlay)
        .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading quoted post")
    }

    private var platformColor: Color { platform.swiftUIColor }

    private var backgroundStyle: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                colorScheme == .dark
                    ? Color.white.opacity(0.15)
                    : Color.black.opacity(0.1),
                lineWidth: 0.5
            )
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.02)
            : Color.black.opacity(0.05)
    }
}

/// Helper to display relative time
struct RelativeTimeView: View {
    let date: Date

    var body: some View {
        Text(date.relativeTimeString)
            .font(.caption)
            .foregroundColor(.secondary)
            // Visual: abbreviated ('6m'). Spoken: full natural language
            // ('6 minutes ago'). Matches PostAuthorView's split-style
            // pattern from iter 114.
            .accessibilityLabel(
                SharedFormatters.relativeFull.localizedString(for: date, relativeTo: Date())
            )
    }
}

/// Helper to display post attachment
private struct PostAttachmentView: View {
    let attachment: Post.Attachment

    var body: some View {
        let stableImageURL = URL(string: attachment.url)
        AsyncImage(url: stableImageURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(MediaConstants.CornerRadius.feed)
                    .clipped()
            } else if phase.error != nil {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(MediaConstants.CornerRadius.feed)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(Color(.systemGray2).gradient)
                            .symbolRenderingMode(.hierarchical)
                    )
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .cornerRadius(MediaConstants.CornerRadius.feed)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .id(stableImageURL?.absoluteString ?? "no-url")
    }
}

#Preview {
    let samplePost = Post(
        id: "preview-1",
        content: "This is a sample quoted post with some longer content to test the display",
        authorName: "John Doe",
        authorUsername: "johndoe",
        authorProfilePictureURL: "",
        createdAt: Date(),
        platform: .mastodon,
        originalURL: "",
        attachments: [],
        mentions: [],
        tags: []
    )

    return VStack(spacing: 16) {
        QuotedPostView(post: samplePost)
        LoadingQuoteView(platform: .bluesky)
        LoadingQuoteView(platform: .mastodon)
    }
    .padding()
}
