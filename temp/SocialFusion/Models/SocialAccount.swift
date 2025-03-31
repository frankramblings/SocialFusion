import Foundation

struct SocialAccount: Identifiable, Equatable, Codable {
    let id: String
    let username: String
    let displayName: String
    let serverURL: String
    let platform: SocialPlatform
    
    // Additional properties that could be added later
    // let avatarURL: URL?
    // let accessToken: String
    // let refreshToken: String?
    // let tokenExpirationDate: Date?
    
    static func == (lhs: SocialAccount, rhs: SocialAccount) -> Bool {
        lhs.id == rhs.id
    }
}