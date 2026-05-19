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
        // Spec: "Onboarding asks: Echo replies by default? with a toggle
        // (default ON)." Onboarding writes a concrete policy when the
        // user makes a choice, but users who never see the page (upgrade
        // path: existing accounts → onboarding gate skips) need a sensible
        // pre-choice default. Echo-on matches the spec's elevated path.
        let raw = userDefaults.string(forKey: defaultsKey) ?? EchoPolicy.echoOn.rawValue
        self.policy = EchoPolicy(rawValue: raw) ?? .echoOn
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
