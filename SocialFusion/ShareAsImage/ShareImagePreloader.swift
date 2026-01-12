import Foundation
import UIKit

/// Pre-loads images for share image rendering to ensure they're available synchronously
@MainActor
public struct ShareImagePreloader {
    
    /// Pre-loads all images needed for a share document
    public static func preloadImages(for document: ShareImageDocument) async {
        var urlsToLoad: [URL] = []
        
        // Collect all avatar URLs
        if let avatarURL = document.selectedPost.authorAvatarURL {
            urlsToLoad.append(avatarURL)
        }
        
        for comment in document.allComments {
            if let avatarURL = comment.authorAvatarURL {
                urlsToLoad.append(avatarURL)
            }
        }
        
        // Collect media thumbnail URLs
        for thumbnail in document.selectedPost.mediaThumbnails {
            if let url = thumbnail.url {
                urlsToLoad.append(url)
            }
        }
        
        // Collect link preview thumbnail URLs
        if let linkPreview = document.selectedPost.linkPreviewData,
           let thumbnailURL = linkPreview.thumbnailURL {
            urlsToLoad.append(thumbnailURL)
        }
        
        // Collect quote post media URLs
        if let quotePost = document.selectedPost.quotePostData {
            for thumbnail in quotePost.mediaThumbnails {
                if let url = thumbnail.url {
                    urlsToLoad.append(url)
                }
            }
        }
        
        // Pre-load all images using ImageCache
        let imageCache = ImageCache.shared
        await withTaskGroup(of: Void.self) { group in
            for url in urlsToLoad {
                group.addTask {
                    // Check if already cached
                    if imageCache.getCachedImage(for: url) == nil {
                        // Load with high priority using Combine publisher
                        let cancellable = imageCache.loadImage(from: url, priority: .high)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { _ in }
                            )
                        // Wait a bit for the image to load
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds max wait
                        _ = cancellable  // Keep reference
                    }
                }
            }
        }
    }
}
