import SwiftUI

/// Sheet that lists existing pins (rename, reorder, swipe-to-delete) and
/// offers a form to create a new cross-network "account group" pin.
public struct PinnedTimelinesEditorView: View {
    @StateObject var viewModel: PinnedTimelineEditorViewModel
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.dismiss) private var dismiss
    @State private var renamingID: String? = nil
    @State private var renameDraft: String = ""

    public init(viewModel: PinnedTimelineEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                existingPinsSection
                createAccountGroupSection
                footerSection
            }
            .navigationTitle("Edit Pins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.store.pins.isEmpty {
                        EditButton()
                    }
                }
            }
        }
    }

    // MARK: - Existing pins section

    private var existingPinsSection: some View {
        Section("Your pins") {
            if viewModel.store.pins.isEmpty {
                Text("No pinned timelines yet. Pin a list or feed from the timeline picker, or create an account group below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.store.pins) { pin in
                    pinRow(pin)
                }
                .onDelete { offsets in
                    for index in offsets {
                        viewModel.delete(id: viewModel.store.pins[index].id)
                    }
                }
                .onMove { source, destination in
                    viewModel.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
    }

    @ViewBuilder
    private func pinRow(_ pin: PinnedTimeline) -> some View {
        if renamingID == pin.id {
            HStack {
                TextField("Name", text: $renameDraft, onCommit: {
                    viewModel.commitRename(id: pin.id, to: renameDraft)
                    renamingID = nil
                })
                .textFieldStyle(.roundedBorder)
                Button("Save") {
                    viewModel.commitRename(id: pin.id, to: renameDraft)
                    renamingID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Cancel") { renamingID = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: kindIcon(for: pin.kind))
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.displayName)
                        .font(.body)
                    Text(kindDescription(for: pin.kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    HapticEngine.tap.trigger()
                    renameDraft = pin.displayName
                    renamingID = pin.id
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Rename \(pin.displayName)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pin.displayName), \(kindDescription(for: pin.kind))")
        }
    }

    private func kindIcon(for kind: PinnedTimelineKind) -> String {
        switch kind {
        case .mastodonList: return "list.bullet.rectangle"
        case .blueskyList: return "list.bullet.rectangle"
        case .blueskyFeed: return "antenna.radiowaves.left.and.right"
        case .accountGroup: return "person.3.fill"
        }
    }

    private func kindDescription(for kind: PinnedTimelineKind) -> String {
        switch kind {
        case .mastodonList: return "Mastodon list"
        case .blueskyList: return "Bluesky list"
        case .blueskyFeed: return "Bluesky feed"
        case .accountGroup(let ids):
            let count = ids.count
            return "Account group · \(count) account\(count == 1 ? "" : "s")"
        }
    }

    // MARK: - Create account-group section

    private var createAccountGroupSection: some View {
        Section("Create account group") {
            TextField("Pin name (e.g. Work)", text: $viewModel.draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
            ForEach(serviceManager.accounts, id: \.id) { account in
                Button {
                    HapticEngine.selection.trigger()
                    viewModel.toggleAccountSelection(account.id)
                } label: {
                    accountRow(account)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accountAccessibilityLabel(account))
            }
            Button {
                HapticEngine.success.trigger()
                viewModel.createAccountGroupPin()
            } label: {
                Label("Create pin", systemImage: "plus.circle.fill")
            }
            .disabled(!viewModel.canCreateAccountGroup)
        }
    }

    private func accountRow(_ account: SocialAccount) -> some View {
        let isSelected = viewModel.draftSelectedAccountIDs.contains(account.id)
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName ?? account.username)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("@\(account.username) · \(account.platform == .mastodon ? "Mastodon" : "Bluesky")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func accountAccessibilityLabel(_ account: SocialAccount) -> String {
        let selected = viewModel.draftSelectedAccountIDs.contains(account.id) ? "selected" : "not selected"
        let network = account.platform == .mastodon ? "Mastodon" : "Bluesky"
        let name = account.displayName ?? account.username
        return "\(name), at \(account.username) on \(network), \(selected)"
    }

    // MARK: - Footer

    private var footerSection: some View {
        Section {
            Text("Pinnable timelines are the entry point to the lens that shapes your feed. The full glass-box rule editor — keyword filters, hashtag rules, mute lists — arrives in a later update.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }
}

#if DEBUG
struct PinnedTimelinesEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let store = PinnedTimelineStore(
            userDefaults: .standard,
            defaultsKey: "pins-preview-\(UUID().uuidString)"
        )
        store.add(PinnedTimeline(displayName: "Work", kind: .accountGroup(accountIds: ["m1", "b1"])))
        store.add(PinnedTimeline(displayName: "Tech news", kind: .mastodonList(accountId: "m1", listId: "list-7")))
        return PinnedTimelinesEditorView(viewModel: PinnedTimelineEditorViewModel(store: store))
            .environmentObject(SocialServiceManager())
    }
}
#endif
