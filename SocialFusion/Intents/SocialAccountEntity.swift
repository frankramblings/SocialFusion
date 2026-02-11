import AppIntents
import Foundation

struct SocialAccountEntity: AppEntity {
    var id: String
    var displayName: String
    var handle: String
    var platform: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "@\(handle) (\(platform))"
        )
    }

    static var defaultQuery = SocialAccountQuery()
}

struct SocialAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SocialAccountEntity] {
        let all = await allAccounts()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SocialAccountEntity] {
        await allAccounts()
    }

    @MainActor
    private func allAccounts() -> [SocialAccountEntity] {
        // Access accounts from UserDefaults-persisted account data
        // SocialServiceManager is an @StateObject so we read from the shared persisted state
        let accounts = loadPersistedAccounts()
        return accounts.map { account in
            SocialAccountEntity(
                id: account.id,
                displayName: account.displayName ?? account.username,
                handle: account.username,
                platform: account.platform.rawValue.capitalized
            )
        }
    }

    @MainActor
    private func loadPersistedAccounts() -> [SocialAccount] {
        // Load accounts the same way SocialServiceManager does on init
        guard let data = UserDefaults.standard.data(forKey: "savedAccounts") else {
            return []
        }
        do {
            return try JSONDecoder().decode([SocialAccount].self, from: data)
        } catch {
            print("SocialAccountQuery: Failed to decode accounts: \(error)")
            return []
        }
    }
}
