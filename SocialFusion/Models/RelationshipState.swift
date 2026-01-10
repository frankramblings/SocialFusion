import Foundation

struct RelationshipState: Codable, Equatable {
    let isFollowing: Bool
    let isFollowedBy: Bool
    let isMuted: Bool
    let isBlocked: Bool

    init(
        isFollowing: Bool = false,
        isFollowedBy: Bool = false,
        isMuted: Bool = false,
        isBlocked: Bool = false
    ) {
        self.isFollowing = isFollowing
        self.isFollowedBy = isFollowedBy
        self.isMuted = isMuted
        self.isBlocked = isBlocked
    }
}
