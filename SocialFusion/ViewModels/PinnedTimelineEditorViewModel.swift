import Combine
import Foundation
import SwiftUI

/// Drives `PinnedTimelinesEditorView`. Holds transient draft state for
/// creating an account-group pin (name + selected account IDs) and forwards
/// rename / delete / reorder operations to the store.
@MainActor
public final class PinnedTimelineEditorViewModel: ObservableObject {
    @Published public var draftName: String = ""
    @Published public var draftSelectedAccountIDs: Set<String> = []

    public let store: PinnedTimelineStore

    public init(store: PinnedTimelineStore) {
        self.store = store
    }

    // MARK: - Account-group pin creation

    public var canCreateAccountGroup: Bool {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !draftSelectedAccountIDs.isEmpty
    }

    public func toggleAccountSelection(_ accountId: String) {
        if draftSelectedAccountIDs.contains(accountId) {
            draftSelectedAccountIDs.remove(accountId)
        } else {
            draftSelectedAccountIDs.insert(accountId)
        }
    }

    public func createAccountGroupPin() {
        guard canCreateAccountGroup else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = PinnedTimeline(
            displayName: name,
            // Sort for stability — two pins with the same accounts have the
            // same storageKey regardless of selection order.
            kind: .accountGroup(accountIds: Array(draftSelectedAccountIDs).sorted())
        )
        store.add(pin)
        draftName = ""
        draftSelectedAccountIDs = []
    }

    // MARK: - Existing-pin operations

    public func commitRename(id: String, to newName: String) {
        store.rename(id: id, to: newName)
    }

    public func delete(id: String) {
        store.remove(id: id)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
    }

    /// Add a pin captured from a non-account-group source (Mastodon list,
    /// Bluesky list, Bluesky feed) using a suggested display name. Used by
    /// the picker's "Pin this" capture surface. Returns the new pin so the
    /// caller can immediately reference it (e.g. to select it in the UI).
    @discardableResult
    public func pinExisting(
        kind: PinnedTimelineKind,
        suggestedName: String
    ) -> PinnedTimeline {
        let pin = PinnedTimeline(displayName: suggestedName, kind: kind)
        store.add(pin)
        return pin
    }
}
