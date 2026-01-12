import Foundation
import SwiftUI

/// Adapter that converts Post models to renderables for share image generation
public struct UnifiedAdapter {
    
    // MARK: - Post to PostRenderable
    
    public static func convertPost(
        _ post: Post,
        hideUsernames: Bool = false,
        userMapping: inout [String: String]  // For anonymization
    ) -> PostRenderable {
        let displayPost = post.originalPost ?? post
        
        // Handle username anonymization
        let (authorDisplayName, authorHandle) = anonymizeUser(
            displayName: displayPost.authorName,
            handle: displayPost.authorUsername,
            id: displayPost.authorId,
            hideUsernames: hideUsernames,
            userMapping: &userMapping
        )
        
        // Build stats string
        let statsString = buildStatsString(
            replies: displayPost.replyCount,
            reposts: displayPost.repostCount,
            likes: displayPost.likeCount
        )
        
        // Build boost banner data
        let boostBannerData: PostRenderable.BoostBannerData? = {
            if let boostedBy = post.boostedBy {
                let (boosterDisplay, boosterHandle) = anonymizeUser(
                    displayName: nil,
                    handle: boostedBy,
                    id: nil,
                    hideUsernames: hideUsernames,
                    userMapping: &userMapping
                )
                return PostRenderable.BoostBannerData(
                    boosterHandle: boosterHandle,
                    boosterDisplayName: boosterDisplay
                )
            }
            return nil
        }()
        
        // Build quote post data
        let quotePostData: PostRenderable.QuotePostData? = {
            guard let quotedPost = displayPost.quotedPost else { return nil }
            let (qDisplayName, qHandle) = anonymizeUser(
                displayName: quotedPost.authorName,
                handle: quotedPost.authorUsername,
                id: quotedPost.authorId,
                hideUsernames: hideUsernames,
                userMapping: &userMapping
            )
            
            let qContent = parseContent(quotedPost.content, platform: quotedPost.platform)
            
            return PostRenderable.QuotePostData(
                authorDisplayName: qDisplayName,
                authorHandle: qHandle,
                content: qContent,
                mediaThumbnails: convertAttachments(quotedPost.attachments)
            )
        }()
        
        // Build media thumbnails
        let mediaThumbnails = convertAttachments(displayPost.attachments)
        
        // Build link preview data
        let linkPreviewData: PostRenderable.LinkPreviewData? = {
            // First try primaryLinkURL (pre-extracted link preview)
            if let url = displayPost.primaryLinkURL {
                return PostRenderable.LinkPreviewData(
                    url: url,
                    title: displayPost.primaryLinkTitle ?? url.host ?? "",
                    description: displayPost.primaryLinkDescription,
                    thumbnailURL: displayPost.primaryLinkThumbnailURL
                )
            }
            
            // Fallback: Try to extract URL from content if primaryLinkURL is missing
            // This handles cases where link preview metadata wasn't extracted but URL exists in content
            let plainText = HTMLString(raw: displayPost.content).plainText
            if let firstURL = extractFirstURL(from: plainText) {
                return PostRenderable.LinkPreviewData(
                    url: firstURL,
                    title: firstURL.host ?? "",
                    description: nil,
                    thumbnailURL: nil
                )
            }
            
            return nil
        }()
        
        // Parse content
        let content = parseContent(displayPost.content, platform: displayPost.platform)
        
        // Get avatar URL
        let avatarURL = URL(string: displayPost.authorProfilePictureURL)
        
        // Format detailed timestamp
        let detailedTimestamp = formatDetailedTimestamp(displayPost.createdAt)
        
        return PostRenderable(
            id: displayPost.id,
            title: nil,  // Context line - set by caller if needed
            contextLabel: nil,  // Set by caller if needed
            authorDisplayName: authorDisplayName,
            authorHandle: authorHandle,
            authorId: displayPost.authorId,
            authorAvatarURL: hideUsernames ? nil : avatarURL,  // Hide avatar when anonymizing
            networkLabel: displayPost.platform == .mastodon ? "Mastodon" : "Bluesky",
            timestampString: formatTimestamp(displayPost.createdAt),
            detailedTimestampString: detailedTimestamp,
            statsString: statsString,
            boostBannerData: boostBannerData,
            quotePostData: quotePostData,
            mediaThumbnails: mediaThumbnails,
            linkPreviewData: linkPreviewData,
            content: content,
            platform: displayPost.platform
        )
    }
    
    // MARK: - Post to CommentRenderable
    
    public static func convertComment(
        _ post: Post,
        depth: Int,
        isSelected: Bool = false,
        hideUsernames: Bool = false,
        userMapping: inout [String: String],
        parentAuthorDisplayName: String? = nil
    ) -> CommentRenderable {
        let (displayName, handle) = anonymizeUser(
            displayName: post.authorName,
            handle: post.authorUsername,
            id: post.authorId,
            hideUsernames: hideUsernames,
            userMapping: &userMapping
        )
        
        let content = parseContent(post.content, platform: post.platform)
        let score = post.likeCount + post.repostCount
        
        // Get avatar URL
        let avatarURL = URL(string: post.authorProfilePictureURL)
        
        return CommentRenderable(
            id: post.id,
            parentID: post.inReplyToID,
            authorID: post.authorId,
            authorDisplayName: displayName,
            authorHandle: handle,
            authorAvatarURL: hideUsernames ? nil : avatarURL,  // Hide avatar when anonymizing
            timestampString: formatTimestamp(post.createdAt),
            score: score,
            content: content,
            depth: depth,
            isSelected: isSelected,
            platform: post.platform,
            parentAuthorDisplayName: parentAuthorDisplayName
        )
    }
    
    // MARK: - Helper Methods
    
    static func anonymizeUser(
        displayName: String?,
        handle: String,
        id: String?,
        hideUsernames: Bool,
        userMapping: inout [String: String]
    ) -> (displayName: String, handle: String) {
        guard hideUsernames else {
            return (displayName ?? handle, handle)
        }
        
        let key = id ?? handle
        if let mapped = userMapping[key] {
            return (mapped, mapped)
        }
        
        let userNumber = userMapping.count + 1
        let mapped = "User \(userNumber)"
        userMapping[key] = mapped
        return (mapped, mapped)
    }
    
    private static func buildStatsString(replies: Int, reposts: Int, likes: Int) -> String {
        var components: [String] = []
        if replies > 0 {
            components.append("\(replies) repl\(replies == 1 ? "y" : "ies")")
        }
        if reposts > 0 {
            components.append("\(reposts) repost\(reposts == 1 ? "" : "s")")
        }
        if likes > 0 {
            components.append("\(likes) like\(likes == 1 ? "" : "s")")
        }
        return components.isEmpty ? "" : components.joined(separator: " • ")
    }
    
    private static func formatTimestamp(_ date: Date) -> String {
        return TimeFormatters.shared.relativeTimeString(from: date)
    }
    
    private static func formatDetailedTimestamp(_ date: Date) -> String {
        return TimeFormatters.shared.detailedDateTimeString(from: date)
    }
    
    private static func parseContent(_ content: String, platform: SocialPlatform) -> AttributedString {
        // For MVP, convert HTML to plain text for Mastodon
        if platform == .mastodon {
            let plainText = HTMLString(raw: content).plainText
            return AttributedString(plainText)
        } else {
            return AttributedString(content)
        }
    }
    
    private static func convertAttachments(_ attachments: [Post.Attachment]) -> [PostRenderable.MediaThumbnail] {
        return attachments.map { attachment in
            let mediaType: PostRenderable.MediaThumbnail.MediaType = {
                switch attachment.type {
                case .image:
                    return .image
                case .video, .gifv:
                    return .video
                case .animatedGIF:
                    return .gif
                case .audio:
                    return .image  // Fallback
                }
            }()
            
            return PostRenderable.MediaThumbnail(
                url: URL(string: attachment.url),
                type: mediaType,
                placeholder: ""  // No description property on Attachment
            )
        }
    }
    
    /// Extracts the first valid URL from text
    private static func extractFirstURL(from text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range),
              let url = match.url else {
            return nil
        }
        return url
    }
}
