import SwiftUI

struct TimelineFeedPickerPopover: View {
    enum Step: Equatable {
        case root
        case accountDetail(SocialAccount)
        case mastodonLists(SocialAccount)
        case blueskyFeeds(SocialAccount)
        case instanceBrowser(SocialAccount)
    }

    @ObservedObject var viewModel: TimelineFeedPickerViewModel
    @Binding var isPresented: Bool
    let selection: TimelineFeedSelection
    let accounts: [SocialAccount]
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]
    let onSelect: (TimelineFeedSelection) -> Void

    @State private var step: Step = .root

    private let width: CGFloat = 260

    var body: some View {
        ZStack {
            switch step {
            case .root:
                NavBarPillDropdown(sections: rootSections, width: width)
                    .onAppear { viewModel.instanceSearchText = "" }
            case .accountDetail(let account):
                accountDetailView(for: account)
            case .mastodonLists(let account):
                listsView(for: account)
            case .blueskyFeeds(let account):
                feedsView(for: account)
            case .instanceBrowser(let account):
                instanceBrowserView(for: account)
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                step = .root
                viewModel.instanceSearchText = ""
            }
        }
    }

    // MARK: - Root Level

    private var rootSections: [NavBarPillDropdownSection] {
        var topItems: [NavBarPillDropdownItem] = [
            NavBarPillDropdownItem(
                id: "unified",
                title: "Unified",
                isSelected: selection == .unified,
                action: { select(.unified) }
            )
        ]

        if mastodonAccounts.count >= 2 {
            topItems.append(NavBarPillDropdownItem(
                id: "all-mastodon",
                title: "All Mastodon",
                isSelected: selection == .allMastodon,
                action: { select(.allMastodon) }
            ))
        }

        if blueskyAccounts.count >= 2 {
            topItems.append(NavBarPillDropdownItem(
                id: "all-bluesky",
                title: "All Bluesky",
                isSelected: selection == .allBluesky,
                action: { select(.allBluesky) }
            ))
        }

        var sections = [NavBarPillDropdownSection(id: "top", header: nil, items: topItems)]

        let accountItems: [NavBarPillDropdownItem] = accounts.map { account in
            let platformIcon = account.platform == .mastodon ? "🐘" : "🦋"
            let name = account.displayName ?? account.username
            let isAccountActive: Bool = {
                switch selection {
                case .mastodon(let id, _): return id == account.id
                case .bluesky(let id, _): return id == account.id
                default: return false
                }
            }()
            return NavBarPillDropdownItem(
                id: "account-\(account.id)",
                title: "\(platformIcon) \(name)",
                isSelected: isAccountActive,
                action: { step = .accountDetail(account) }
            )
        }

        if !accountItems.isEmpty {
            sections.append(NavBarPillDropdownSection(id: "accounts", header: nil, items: accountItems))
        }

        return sections
    }

    // MARK: - Account Detail (drill-in)

    private func accountDetailView(for account: SocialAccount) -> some View {
        NavBarPillDropdownContainer(width: width) {
            drillInHeader(title: account.displayName ?? account.username, backTo: .root)
            Divider().padding(.horizontal, 12)

            if account.platform == .mastodon {
                mastodonFeedItems(for: account)
            } else {
                blueskyFeedItems(for: account)
            }
        }
    }

    @ViewBuilder
    private func mastodonFeedItems(for account: SocialAccount) -> some View {
        let aid = account.id
        NavBarPillDropdownRow(
            title: "Home",
            isSelected: selection == .mastodon(accountId: aid, feed: .home),
            action: { select(.mastodon(accountId: aid, feed: .home)) }
        )
        Divider().padding(.horizontal, 12)
        NavBarPillDropdownRow(
            title: "Local",
            isSelected: selection == .mastodon(accountId: aid, feed: .local),
            action: { select(.mastodon(accountId: aid, feed: .local)) }
        )
        Divider().padding(.horizontal, 12)
        NavBarPillDropdownRow(
            title: "Federated",
            isSelected: selection == .mastodon(accountId: aid, feed: .federated),
            action: { select(.mastodon(accountId: aid, feed: .federated)) }
        )
        Divider().padding(.horizontal, 12)
        NavBarPillDropdownRow(
            title: "Lists…",
            isSelected: false,
            action: { step = .mastodonLists(account) }
        )
        Divider().padding(.horizontal, 12)
        NavBarPillDropdownRow(
            title: "Browse Instance…",
            isSelected: false,
            action: { step = .instanceBrowser(account) }
        )
    }

    @ViewBuilder
    private func blueskyFeedItems(for account: SocialAccount) -> some View {
        let aid = account.id
        NavBarPillDropdownRow(
            title: "Following",
            isSelected: selection == .bluesky(accountId: aid, feed: .following),
            action: { select(.bluesky(accountId: aid, feed: .following)) }
        )
        Divider().padding(.horizontal, 12)
        NavBarPillDropdownRow(
            title: "My Feeds…",
            isSelected: false,
            action: { step = .blueskyFeeds(account) }
        )
    }

    // MARK: - Lists (Mastodon)

    private func listsView(for account: SocialAccount) -> some View {
        NavBarPillDropdownContainer(width: width) {
            drillInHeader(title: "Lists", backTo: .accountDetail(account))
            Divider().padding(.horizontal, 12)

            if viewModel.isLoadingLists(for: account.id) {
                ProgressView()
                    .padding(.vertical, 16)
            } else if viewModel.lists(for: account.id).isEmpty {
                Text("No lists found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                let lists = viewModel.lists(for: account.id)
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    NavBarPillDropdownRow(
                        title: list.title,
                        isSelected: isSelectedList(accountId: account.id, listId: list.id),
                        action: {
                            select(.mastodon(accountId: account.id, feed: .list(id: list.id, title: list.title)))
                        }
                    )
                    if index < lists.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadMastodonLists(for: account) }
        }
    }

    // MARK: - Feeds (Bluesky)

    private func feedsView(for account: SocialAccount) -> some View {
        NavBarPillDropdownContainer(width: width) {
            drillInHeader(title: "My Feeds", backTo: .accountDetail(account))
            Divider().padding(.horizontal, 12)

            if viewModel.isLoadingFeeds(for: account.id) {
                ProgressView()
                    .padding(.vertical, 16)
            } else if viewModel.feeds(for: account.id).isEmpty {
                Text("No feeds found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                let feeds = viewModel.feeds(for: account.id)
                ForEach(Array(feeds.enumerated()), id: \.element.uri) { index, feed in
                    NavBarPillDropdownRow(
                        title: feed.displayName,
                        isSelected: isSelectedFeed(accountId: account.id, feedUri: feed.uri),
                        action: {
                            select(.bluesky(accountId: account.id, feed: .custom(uri: feed.uri, name: feed.displayName)))
                        }
                    )
                    if index < feeds.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadBlueskyFeeds(for: account) }
        }
    }

    // MARK: - Instance Browser

    private func instanceBrowserView(for account: SocialAccount) -> some View {
        NavBarPillDropdownContainer(width: width, maxHeight: 360) {
            drillInHeader(title: "Browse Instance", backTo: .accountDetail(account))
            Divider().padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 10) {
                TextField("mastodon.social", text: $viewModel.instanceSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .onSubmit {
                        if let server = viewModel.normalizedInstance(from: viewModel.instanceSearchText) {
                            selectInstance(server, for: account)
                        }
                    }

                if let server = viewModel.normalizedInstance(from: viewModel.instanceSearchText) {
                    NavBarPillDropdownRow(
                        title: "Instance: \(server)",
                        isSelected: isSelectedInstance(accountId: account.id, server: server),
                        action: { selectInstance(server, for: account) }
                    )
                }

                if !viewModel.recentInstances.isEmpty {
                    Text("Recently Browsed")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    ForEach(Array(viewModel.recentInstances.enumerated()), id: \.element) { index, server in
                        NavBarPillDropdownRow(
                            title: "Instance: \(server)",
                            isSelected: isSelectedInstance(accountId: account.id, server: server),
                            action: { selectInstance(server, for: account) }
                        )
                        if index < viewModel.recentInstances.count - 1 {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers

    private func drillInHeader(title: String, backTo: Step) -> some View {
        HStack(spacing: 8) {
            Button(action: { step = backTo }) {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func select(_ selection: TimelineFeedSelection) {
        onSelect(selection)
        dismiss()
    }

    private func selectInstance(_ server: String, for account: SocialAccount) {
        viewModel.recordRecentInstance(server)
        onSelect(.mastodon(accountId: account.id, feed: .instance(server: server)))
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func isSelectedList(accountId: String, listId: String) -> Bool {
        if case .mastodon(let id, .list(let lid, _)) = selection {
            return id == accountId && lid == listId
        }
        return false
    }

    private func isSelectedFeed(accountId: String, feedUri: String) -> Bool {
        if case .bluesky(let id, .custom(let uri, _)) = selection {
            return id == accountId && uri == feedUri
        }
        return false
    }

    private func isSelectedInstance(accountId: String, server: String) -> Bool {
        if case .mastodon(let id, .instance(let s)) = selection {
            return id == accountId && s == server
        }
        return false
    }
}
