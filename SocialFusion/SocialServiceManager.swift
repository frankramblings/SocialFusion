func loadAccounts() {
    print("Loading accounts from keychain...")
    // Load Mastodon accounts
    mastodonAccounts = MastodonAccountService.shared.loadAccounts()
    print("Loaded \(mastodonAccounts.count) Mastodon accounts")

    // Load Bluesky accounts
    blueskyAccounts = BlueskyAccountService.shared.loadAccounts()
    print("Loaded \(blueskyAccounts.count) Bluesky accounts")

    // Load selected account IDs from UserDefaults
    let storedIds = UserDefaults.standard.array(forKey: "selectedAccountIds") as? [String] ?? []
    print("Loaded \(storedIds.count) account selections from UserDefaults")

    // Check if stored IDs exist in our loaded accounts
    let validIds = storedIds.filter { id in
        let exists =
            mastodonAccounts.contains(where: { $0.id == id })
            || blueskyAccounts.contains(where: { $0.id == id })
        return exists
    }

    // Use valid IDs if any exist, otherwise default to empty array
    // This prevents using account IDs that don't exist in the app
    if !validIds.isEmpty {
        selectedAccountIds = validIds
    } else {
        // Reset selected accounts if none are valid
        selectedAccountIds = []
        UserDefaults.standard.set([], forKey: "selectedAccountIds")
    }

    print(
        "SocialServiceManager initialized with \(mastodonAccounts.count) Mastodon accounts and \(blueskyAccounts.count) Bluesky accounts"
    )
    print("Selected account IDs: \(selectedAccountIds.joined(separator: ", "))")
}
