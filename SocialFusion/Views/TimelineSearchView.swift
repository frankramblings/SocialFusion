import SwiftUI

/// Modal overlay that hosts the two-layer timeline search experience.
///
/// Layered into a sheet (presented from `ConsolidatedTimelineView`), the
/// view owns a `TimelineSearchViewModel`, plumbs a `TextField` to its
/// `setQuery(_:)`, and renders the `sections` it publishes.
struct TimelineSearchView: View {

    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var fusedMomentStore: FusedMomentStore
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()

    @StateObject private var viewModel: TimelineSearchViewModel
    @Binding private var isPresented: Bool
    @FocusState private var fieldFocused: Bool

    @State private var replyingToPost: Post? = nil
    @State private var quotingToPost: Post? = nil

    init(
        viewModel: @autoclosure @escaping () -> TimelineSearchViewModel,
        isPresented: Binding<Bool>
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _isPresented = isPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            content
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear { fieldFocused = true }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search this timeline and beyond", text: Binding(
                get: { viewModel.query },
                set: { viewModel.setQuery($0) }
            ))
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .focused($fieldFocused)
            .accessibilityIdentifier("TimelineSearchField")
            .accessibilityLabel("Search timeline and beyond")

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.setQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button("Cancel") {
                viewModel.setQuery("")
                isPresented = false
            }
            .accessibilityLabel("Dismiss search")
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .idle:
            idleState
        case .debouncing, .filtering:
            resultsList
                .overlay(alignment: .top) {
                    if viewModel.sections.isEmpty {
                        ProgressView().padding(.top, 16)
                    }
                }
        case .clientResultsOnly:
            VStack(spacing: 0) {
                resultsList
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching Mastodon and Bluesky…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        case .complete:
            resultsList
                .overlay(alignment: .center) {
                    if viewModel.sections.isEmpty {
                        emptyResultsState
                    }
                }
        case .clientResultsOnlyFailed:
            VStack(spacing: 0) {
                resultsList
                Text("Couldn't reach the networks. Showing only what's loaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Search posts in your timeline and across Mastodon and Bluesky.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.subheadline.weight(.semibold))
            Text("Try a different word or check spelling.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.sections) { section in
                    Section(header: header(for: section)) {
                        ForEach(section.hits) { hit in
                            postCardView(for: hit.post)
                                .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func header(for section: TimelineSearchSection) -> some View {
        switch section {
        case .client(let hits):
            TimelineSearchSectionHeader(kind: .client, resultCount: hits.count)
        case .remote(let platform, let hits):
            TimelineSearchSectionHeader(
                kind: .remote(platform: platform),
                resultCount: hits.count
            )
        }
    }

    // MARK: - Post Card (mirrors SearchView's wiring)

    private func postCardView(for post: Post) -> some View {
        let entryKind: TimelineEntryKind
        if post.originalPost != nil || post.boostedBy != nil {
            let boostedByHandle = post.boostedBy ?? post.authorUsername
            entryKind = .boost(boostedBy: boostedByHandle)
        } else if let parentId = post.inReplyToID {
            entryKind = .reply(parentId: parentId)
        } else {
            entryKind = .normal
        }

        let entry = TimelineEntry(
            id: post.id,
            kind: entryKind,
            post: post,
            createdAt: post.createdAt
        )

        return PostCardView(
            entry: entry,
            postActionStore: serviceManager.postActionStore,
            postActionCoordinator: serviceManager.postActionCoordinator,
            layoutSnapshot: nil,
            onPostTap: { navigationEnvironment.navigateToPostFusedAware(post, fusedMomentStore: fusedMomentStore) },
            onParentPostTap: { parent in
                navigationEnvironment.navigateToPostFusedAware(parent, fusedMomentStore: fusedMomentStore)
            },
            onAuthorTap: { navigationEnvironment.navigateToUser(from: post) },
            onReply: { replyingToPost = post.originalPost ?? post },
            onRepost: {
                Task {
                    do {
                        _ = try await serviceManager.repostPost(post)
                    } catch {
                        ErrorHandler.shared.handleError(error)
                    }
                }
            },
            onLike: {
                Task {
                    do {
                        _ = try await serviceManager.likePost(post)
                    } catch {
                        ErrorHandler.shared.handleError(error)
                    }
                }
            },
            onShare: { post.presentShareSheet() },
            onOpenInBrowser: { post.openInBrowser() },
            onCopyLink: { post.copyLink() },
            onReport: { post.report(via: serviceManager) },
            onQuote: { quotingToPost = post }
        )
    }
}
