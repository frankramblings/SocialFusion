import Foundation
import SwiftUI

/// Coordinates share-as-image functionality
@MainActor
public struct ShareAsImageCoordinator {
    
    /// Builds a share image document from a post and presents the sheet
    static func presentShareSheet(
        for post: Post,
        threadContext: ThreadContext? = nil,
        serviceManager: SocialServiceManager
    ) async -> ShareImageDocument? {
        // Build initial config
        let config = ShareImageConfig()
        var userMapping: [String: String] = [:]
        
        // Build document
        let document = ShareThreadRenderBuilder.buildDocument(
            from: post,
            threadContext: threadContext,
            config: config,
            userMapping: &userMapping
        )
        
        return document
    }
    
    /// Builds a share image document from a selected comment in a thread
    static func presentShareSheet(
        for selectedPost: Post,
        threadContext: ThreadContext,
        serviceManager: SocialServiceManager
    ) async -> ShareImageDocument? {
        // Build initial config
        let config = ShareImageConfig()
        var userMapping: [String: String] = [:]
        
        // Build document
        let document = ShareThreadRenderBuilder.buildDocument(
            from: selectedPost,
            threadContext: threadContext,
            config: config,
            userMapping: &userMapping
        )
        
        return document
    }
}
