import SwiftUI

/// Coordinates fullscreen media presentation across the app
/// Allows fullscreen views to be presented at the root level while maintaining hero transitions
class FullscreenMediaCoordinator: ObservableObject {
    @Published var selectedMedia: Post.Attachment?
    @Published var allMedia: [Post.Attachment] = []
    @Published var showFullscreen: Bool = false
    @Published var showAltTextInitially: Bool = false
    @Published var dismissalDirection: CGSize = CGSize(width: 0, height: 1)
    
    // Hero transition support - namespace must be passed from the source view
    var mediaNamespace: Namespace.ID?
    var thumbnailFrames: [String: ThumbnailFrameInfo] = [:]
    
    func present(
        media: Post.Attachment,
        allMedia: [Post.Attachment],
        showAltTextInitially: Bool = false,
        mediaNamespace: Namespace.ID? = nil,
        thumbnailFrames: [String: ThumbnailFrameInfo] = [:]
    ) {
        self.selectedMedia = media
        self.allMedia = allMedia
        self.showAltTextInitially = showAltTextInitially
        self.mediaNamespace = mediaNamespace
        self.thumbnailFrames = thumbnailFrames
        self.showFullscreen = true
    }
    
    func dismiss() {
        showFullscreen = false
        showAltTextInitially = false
        // Small delay to allow animations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.selectedMedia = nil
            self.allMedia = []
            self.mediaNamespace = nil
            self.thumbnailFrames = [:]
        }
    }
}

