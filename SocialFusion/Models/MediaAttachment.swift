import Foundation

/// Represents a media attachment for a post
struct MediaAttachment: Identifiable, Equatable {
    /// The type of media
    enum MediaType: String, Codable {
        case image
        case video
        case audio
        case animatedGIF
        case unknown
    }

    let id: String
    let type: MediaType
    let url: URL
    let previewURL: URL?
    let altText: String?

    init(id: String, type: MediaType, url: URL, previewURL: URL? = nil, altText: String? = nil) {
        self.id = id
        self.type = type
        self.url = url
        self.previewURL = previewURL
        self.altText = altText
    }
}

/// Represents the type of media
enum MediaType: String, Codable {
    case image
    case video
    case audio
    case animatedGIF
    case unknown
}
