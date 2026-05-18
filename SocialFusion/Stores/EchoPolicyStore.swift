import Combine
import Foundation

public enum EchoPolicy: String, Codable, CaseIterable {
    case echoOn          // Both networks pre-checked.
    case echoOff         // Only the original-side network pre-checked.
    case askEachTime     // Neither pre-checked; Send disabled until user picks.
}

@MainActor
public final class EchoPolicyStore: ObservableObject {
    @Published public var policy: EchoPolicy {
        didSet {
            userDefaults.set(policy.rawValue, forKey: defaultsKey)
        }
    }

    private let userDefaults: UserDefaults
    private let defaultsKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "echo.reply.policy"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        let raw = userDefaults.string(forKey: defaultsKey) ?? EchoPolicy.askEachTime.rawValue
        self.policy = EchoPolicy(rawValue: raw) ?? .askEachTime
    }

    /// Returns the set of platforms to pre-check in a Fused reply composer,
    /// given the platform the user is replying *from*.
    public func initialReplyTargets(originalPlatform: SocialPlatform) -> Set<SocialPlatform> {
        switch policy {
        case .echoOn: return [.mastodon, .bluesky]
        case .echoOff: return [originalPlatform]
        case .askEachTime: return []
        }
    }
}
