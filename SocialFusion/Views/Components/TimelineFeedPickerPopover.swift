import SwiftUI

struct TimelineFeedPickerPopover: View {
    enum Step: Equatable {
        case root
        case accountDetail(SocialAccount)
        case mastodonLists(SocialAccount)
        case blueskyFeeds(SocialAccount)
        case blueskyLists(SocialAccount)
        case instanceBrowser(SocialAccount)
    }

    @ObservedObject var viewModel: TimelineFeedPickerViewModel
    @Binding var isPresented: Bool
    let selection: TimelineFeedSelection
    let accounts: [SocialAccount]
    let mastodonAccounts: [SocialAccount]
    let blueskyAccounts: [SocialAccount]
    let onSelect: (TimelineFeedSelection) -> Void
    /// Called when the user taps "Edit Pins…" — the host should present
    /// `PinnedTimelinesEditorView`. Default no-op so callers that haven't
    /// migrated yet keep compiling; Task 11 wires the real handler.
    var onEditPins: () -> Void = { }

    @EnvironmentObject private var pinnedTimelineStore: PinnedTimelineStore
    @State private var step: Step = .root

    private let width: CGFloat = 260

    var body: some View {
        ZStack(alignment: .top) {
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
            case .blueskyLists(let account):
                blueskyListsView(for: account)
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
        var sections: [NavBarPillDropdownSection] = []

        // Pinned section comes first — it's the user's curated view, so
        // it should be the most visible affordance at the picker root.
        if let pinned = pinnedSection {
            sections.append(pinned)
        }

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

        sections.append(NavBarPillDropdownSection(id: "top", header: nil, items: topItems))

        let accountItems: [NavBarPillDropdownItem] = accounts.map { account in
            let logoAsset = account.platform == .mastodon ? "MastodonLogo" : "BlueskyLogo"
            let isAccountActive: Bool = {
                switch selection {
                case .mastodon(let id, _): return id == account.id
                case .bluesky(let id, _): return id == account.id
                default: return false
                }
            }()
            return NavBarPillDropdownItem(
                id: "account-\(account.id)",
                icon: logoAsset,
                title: "@\(account.username)",
                isSelected: isAccountActive,
                showChevron: true,
                action: { step = .accountDetail(account) }
            )
        }

        if !accountItems.isEmpty {
            sections.append(NavBarPillDropdownSection(id: "accounts", header: nil, items: accountItems))
        }

        return sections
    }

    /// Returns the Pinned section if the user has any pins, otherwise nil
    /// so the rootSections caller can skip it cleanly.
    private var pinnedSection: NavBarPillDropdownSection? {
        guard !pinnedTimelineStore.pins.isEmpty else { return nil }
        var items: [NavBarPillDropdownItem] = pinnedTimelineStore.pins.map { pin in
            NavBarPillDropdownItem(
                id: "pinned-\(pin.id)",
                title: pin.displayName,
                isSelected: selection == .pinned(id: pin.id),
                action: { select(.pinned(id: pin.id)) }
            )
        }
        items.append(
            NavBarPillDropdownItem(
                id: "edit-pins",
                title: "Edit Pins…",
                isSelected: false,
                action: {
                    HapticEngine.tap.trigger()
                    dismiss()
                    onEditPins()
                }
            )
        )
        return NavBarPillDropdownSection(id: "pinned", header: "Pinned", items: items)
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
        Divider().padding(.horizontal, 12)
        NavBarPillDropdownRow(
            title: "My Lists…",
            isSelected: false,
            action: { step = .blueskyLists(account) }
        )
    }

    // MARK: - Lists (Mastodon)

    private func listsView(for account: SocialAccount) -> some View {
        NavBarPillDropdownContainer(width: width, maxHeight: 400) {
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
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                            let kind = PinnedTimelineKind.mastodonList(accountId: account.id, listId: list.id)
                            NavBarPillDropdownRow(
                                title: list.title,
                                isSelected: isSelectedList(accountId: account.id, listId: list.id),
                                action: {
                                    select(.mastodon(accountId: account.id, feed: .list(id: list.id, title: list.title)))
                                }
                            )
                            .contextMenu {
                                pinThisMenuItem(kind: kind, suggestedName: list.title)
                            }
                            if index < lists.count - 1 {
                                Divider().padding(.horizontal, 12)
                            }
                        }
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
        NavBarPillDropdownContainer(width: width, maxHeight: 400) {
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
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(feeds.enumerated()), id: \.element.uri) { index, feed in
                            let kind = PinnedTimelineKind.blueskyFeed(accountId: account.id, feedUri: feed.uri)
                            NavBarPillDropdownRow(
                                title: feed.displayName,
                                isSelected: isSelectedFeed(accountId: account.id, feedUri: feed.uri),
                                action: {
                                    select(.bluesky(accountId: account.id, feed: .custom(uri: feed.uri, name: feed.displayName)))
                                }
                            )
                            .contextMenu {
                                pinThisMenuItem(kind: kind, suggestedName: feed.displayName)
                            }
                            if index < feeds.count - 1 {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadBlueskyFeeds(for: account) }
        }
    }

    // MARK: - Lists (Bluesky)

    private func blueskyListsView(for account: SocialAccount) -> some View {
        NavBarPillDropdownContainer(width: width, maxHeight: 400) {
            drillInHeader(title: "My Lists", backTo: .accountDetail(account))
            Divider().padding(.horizontal, 12)

            if viewModel.isLoadingBlueskyLists(for: account.id) {
                ProgressView()
                    .padding(.vertical, 16)
            } else if viewModel.blueskyLists(for: account.id).isEmpty {
                Text("No lists found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
            } else {
                let lists = viewModel.blueskyLists(for: account.id)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(lists.enumerated()), id: \.element.uri) { index, list in
                            let kind = PinnedTimelineKind.blueskyList(accountId: account.id, listUri: list.uri)
                            // Bluesky lists aren't first-class
                            // TimelineFeedSelection cases — they're
                            // pinned-only. So tapping a list row pins
                            // it immediately and selects the new pin.
                            NavBarPillDropdownRow(
                                title: list.name,
                                isSelected: pinnedTimelineStore.isPinned(kind: kind),
                                action: {
                                    pinIfNeededAndSelect(kind: kind, suggestedName: list.name)
                                }
                            )
                            .contextMenu {
                                pinThisMenuItem(kind: kind, suggestedName: list.name)
                            }
                            if index < lists.count - 1 {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadBlueskyLists(for: account) }
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
            Button {
                HapticEngine.selection.trigger()
                step = backTo
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    // Visual 28pt; outer 44pt extends hit area to
                    // the HIG minimum. Same pattern as PostMenu
                    // (a86637c) and SearchChipRow (62055bc).
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Back")
            .accessibilityHint("Returns to the previous feed-picker step")

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                // Drill-in section header — mark as a heading so
                // VoiceOver users can navigate to it via the
                // Headings rotor.
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Builds the "Pin this" / "Unpin" context-menu item used by every
    /// pinnable row (Mastodon lists, Bluesky feeds, Bluesky lists).
    @ViewBuilder
    private func pinThisMenuItem(kind: PinnedTimelineKind, suggestedName: String) -> some View {
        if pinnedTimelineStore.isPinned(kind: kind) {
            Button(role: .destructive) {
                if let pin = pinnedTimelineStore.pins.first(where: { $0.kind == kind }) {
                    HapticEngine.warning.trigger()
                    pinnedTimelineStore.remove(id: pin.id)
                }
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        } else {
            Button {
                HapticEngine.success.trigger()
                pinnedTimelineStore.add(PinnedTimeline(displayName: suggestedName, kind: kind))
            } label: {
                Label("Pin this", systemImage: "pin")
            }
        }
    }

    /// Bluesky lists path: tapping the row pins the list (if not already)
    /// and selects the new pin so the timeline updates immediately. This
    /// is the only entry point that pins-as-side-effect — lists/feeds with
    /// first-class selection cases stay tap-to-select, long-press-to-pin.
    private func pinIfNeededAndSelect(kind: PinnedTimelineKind, suggestedName: String) {
        let pinId: String
        if let existing = pinnedTimelineStore.pins.first(where: { $0.kind == kind }) {
            pinId = existing.id
        } else {
            let pin = PinnedTimeline(displayName: suggestedName, kind: kind)
            pinnedTimelineStore.add(pin)
            pinId = pin.id
        }
        select(.pinned(id: pinId))
    }

    private func select(_ selection: TimelineFeedSelection) {
        // Selection haptic on feed change — matches the
        // NavBarPillDropdownRow haptic pattern and the iOS Picker
        // convention. The dismissal animation is good visual feedback
        // but the haptic confirms the choice landed before the
        // animation finishes.
        HapticEngine.selection.trigger()
        onSelect(selection)
        dismiss()
    }

    private func selectInstance(_ server: String, for account: SocialAccount) {
        HapticEngine.selection.trigger()
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
