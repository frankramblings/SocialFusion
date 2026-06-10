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

    /// Pending post-dismissal cleanup. Held so a re-present can cancel it before
    /// it nils out freshly-set media (which would strand the user on a blank,
    /// undismissable fullscreen cover).
    private var pendingCleanup: DispatchWorkItem?

    func present(
        media: Post.Attachment,
        allMedia: [Post.Attachment],
        showAltTextInitially: Bool = false,
        mediaNamespace: Namespace.ID? = nil,
        thumbnailFrames: [String: ThumbnailFrameInfo] = [:]
    ) {
        // Cancel any in-flight cleanup from a just-dismissed presentation so it
        // can't clobber the state we're about to set.
        pendingCleanup?.cancel()
        pendingCleanup = nil

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
        // Small delay to allow animations to complete. Tracked so present() can
        // cancel it if the user re-opens media mid-dismissal.
        pendingCleanup?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.selectedMedia = nil
            self.allMedia = []
            self.mediaNamespace = nil
            self.thumbnailFrames = [:]
            self.pendingCleanup = nil
        }
        pendingCleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

