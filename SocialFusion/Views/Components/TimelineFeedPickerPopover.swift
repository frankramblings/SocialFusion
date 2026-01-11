import SwiftUI

struct TimelineFeedPickerPopover: View {
    enum Step: Equatable {
        case root
        case mastodonLists
        case blueskyFeeds
        case instanceBrowser
    }

    @ObservedObject var viewModel: TimelineFeedPickerViewModel
    @Binding var isPresented: Bool
    let scope: TimelineScope
    let selection: TimelineFeedSelection
    let account: SocialAccount?
    let onSelect: (TimelineFeedSelection) -> Void

    @State private var step: Step = .root

    private let width: CGFloat = 260

    var body: some View {
        ZStack {
            switch step {
            case .root:
                NavBarPillDropdown(sections: rootSections, width: width)
                    .onAppear {
                        viewModel.instanceSearchText = ""
                    }
            case .mastodonLists:
                listsView
            case .blueskyFeeds:
                feedsView
            case .instanceBrowser:
                instanceBrowserView
            }
        }
        .onChange(of: scope) { _ in
            step = .root
            viewModel.instanceSearchText = ""
        }
        .onChange(of: isPresented) { presented in
            if presented {
                step = .root
                viewModel.instanceSearchText = ""
            }
        }
    }

    private var rootSections: [NavBarPillDropdownSection] {
        switch scope {
        case .allAccounts:
            return [
                NavBarPillDropdownSection(
                    id: "timeline-unified",
                    header: nil,
                    items: [
                        NavBarPillDropdownItem(
                            id: "timeline-unified",
                            title: "Unified",
                            isSelected: selection == .unified,
                            action: { select(.unified) }
                        )
                    ]
                )
            ]
        case .account:
            if let account = account, account.platform == .mastodon {
                return [
                    NavBarPillDropdownSection(
                        id: "timeline-mastodon",
                        header: nil,
                        items: [
                            NavBarPillDropdownItem(
                                id: "timeline-mastodon-home",
                                title: "Home",
                                isSelected: isSelectedMastodon(.home),
                                action: { select(.mastodon(.home)) }
                            ),
                            NavBarPillDropdownItem(
                                id: "timeline-mastodon-local",
                                title: "Local",
                                isSelected: isSelectedMastodon(.local),
                                action: { select(.mastodon(.local)) }
                            ),
                            NavBarPillDropdownItem(
                                id: "timeline-mastodon-federated",
                                title: "Federated",
                                isSelected: isSelectedMastodon(.federated),
                                action: { select(.mastodon(.federated)) }
                            ),
                            NavBarPillDropdownItem(
                                id: "timeline-mastodon-lists",
                                title: "Lists...",
                                isSelected: false,
                                action: { openLists() }
                            ),
                            NavBarPillDropdownItem(
                                id: "timeline-mastodon-instance",
                                title: "Browse Instance Timeline...",
                                isSelected: false,
                                action: { step = .instanceBrowser }
                            ),
                        ]
                    )
                ]
            }

            if let account = account, account.platform == .bluesky {
                return [
                    NavBarPillDropdownSection(
                        id: "timeline-bluesky",
                        header: nil,
                        items: [
                            NavBarPillDropdownItem(
                                id: "timeline-bluesky-following",
                                title: "Following",
                                isSelected: isSelectedBluesky(.following),
                                action: { select(.bluesky(.following)) }
                            ),
                            NavBarPillDropdownItem(
                                id: "timeline-bluesky-feeds",
                                title: "My Feeds...",
                                isSelected: false,
                                action: { openFeeds() }
                            ),
                        ]
                    )
                ]
            }

            return []
        }
    }

    private var listsView: some View {
        NavBarPillDropdownContainer(width: width) {
            drillInHeader(title: "Lists")
            Divider()
                .padding(.horizontal, 12)

            if viewModel.isLoadingLists {
                ProgressView()
                    .padding(.vertical, 16)
            } else if viewModel.mastodonLists.isEmpty {
                Text("No lists found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(viewModel.mastodonLists.enumerated()), id: \.element.id) {
                    index, list in
                    NavBarPillDropdownRow(
                        title: list.title,
                        isSelected: isSelectedMastodonList(list.id),
                        action: {
                            select(.mastodon(.list(id: list.id, title: list.title)))
                        }
                    )

                    if index < viewModel.mastodonLists.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .onAppear {
            if let account = account {
                Task { await viewModel.loadMastodonLists(for: account) }
            }
        }
    }

    private var feedsView: some View {
        NavBarPillDropdownContainer(width: width) {
            drillInHeader(title: "My Feeds")
            Divider()
                .padding(.horizontal, 12)

            if viewModel.isLoadingFeeds {
                ProgressView()
                    .padding(.vertical, 16)
            } else if viewModel.blueskyFeeds.isEmpty {
                Text("No feeds found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(viewModel.blueskyFeeds.enumerated()), id: \.element.uri) {
                    index, feed in
                    NavBarPillDropdownRow(
                        title: feed.displayName,
                        isSelected: isSelectedBlueskyFeed(feed.uri),
                        action: {
                            select(.bluesky(.custom(uri: feed.uri, name: feed.displayName)))
                        }
                    )

                    if index < viewModel.blueskyFeeds.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .onAppear {
            if let account = account {
                Task { await viewModel.loadBlueskyFeeds(for: account) }
            }
        }
    }

    private var instanceBrowserView: some View {
        NavBarPillDropdownContainer(width: width, maxHeight: 360) {
            drillInHeader(title: "Browse Instance")
            Divider()
                .padding(.horizontal, 12)

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
                        if let server = viewModel.normalizedInstance(from: viewModel.instanceSearchText)
                        {
                            selectInstance(server)
                        }
                    }

                if let server = viewModel.normalizedInstance(from: viewModel.instanceSearchText) {
                    NavBarPillDropdownRow(
                        title: "Instance: \(server)",
                        isSelected: isSelectedMastodonInstance(server),
                        action: { selectInstance(server) }
                    )
                }

                if !viewModel.recentInstances.isEmpty {
                    Text("Recently Browsed")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    ForEach(Array(viewModel.recentInstances.enumerated()), id: \.element) {
                        index, server in
                        NavBarPillDropdownRow(
                            title: "Instance: \(server)",
                            isSelected: isSelectedMastodonInstance(server),
                            action: { selectInstance(server) }
                        )

                        if index < viewModel.recentInstances.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func drillInHeader(title: String) -> some View {
        HStack(spacing: 8) {
            Button(action: { step = .root }) {
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

    private func openLists() {
        step = .mastodonLists
    }

    private func openFeeds() {
        step = .blueskyFeeds
    }

    private func select(_ selection: TimelineFeedSelection) {
        onSelect(selection)
        dismiss()
    }

    private func selectInstance(_ server: String) {
        viewModel.recordRecentInstance(server)
        onSelect(.mastodon(.instance(server: server)))
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func isSelectedMastodon(_ feed: MastodonTimelineFeed) -> Bool {
        if case .mastodon(let current) = selection {
            return current == feed
        }
        return false
    }

    private func isSelectedMastodonList(_ listId: String) -> Bool {
        if case .mastodon(.list(let id, _)) = selection {
            return id == listId
        }
        return false
    }

    private func isSelectedMastodonInstance(_ server: String) -> Bool {
        if case .mastodon(.instance(let current)) = selection {
            return current == server
        }
        return false
    }

    private func isSelectedBluesky(_ feed: BlueskyTimelineFeed) -> Bool {
        if case .bluesky(let current) = selection {
            return current == feed
        }
        return false
    }

    private func isSelectedBlueskyFeed(_ uri: String) -> Bool {
        if case .bluesky(.custom(let current, _)) = selection {
            return current == uri
        }
        return false
    }
}
