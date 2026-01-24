import SwiftUI

/// Splits long threads into multiple page documents for multi-image export
@MainActor
public struct ThreadPaginator {

    /// A page of content for rendering
    public struct Page {
        /// Page index (0-based)
        public let index: Int
        /// Total number of pages
        public let totalPages: Int
        /// The document for this page
        public let document: ShareImageDocument
        /// The preset to use for this page
        public let preset: ShareCanvasPreset
    }

    // MARK: - Configuration

    /// Target preset for paginated output
    private static let targetPreset: ShareCanvasPreset = .ratio9x16

    /// Short side dimension
    private static let shortSide: CGFloat = 1080

    /// Estimated height per comment (in pixels at full scale)
    private static let estimatedCommentHeight: CGFloat = 100

    /// Minimum comments per page (to avoid tiny pages)
    private static let minCommentsPerPage = 2

    // MARK: - Public API

    /// Paginate a document into multiple pages that each fit in the target preset
    /// - Parameter document: The original document to paginate
    /// - Returns: Array of pages, or single page if pagination not needed
    public static func paginate(
        document: ShareImageDocument
    ) -> [Page] {
        // If no pagination needed, return single page
        let selection = AutoPresetPicker.selectPreset(for: document)
        if !selection.shouldPaginate {
            return [Page(
                index: 0,
                totalPages: 1,
                document: document,
                preset: selection.preset
            )]
        }

        // Calculate available height for content
        let maxCardHeight = SafeInsetCalculator.maxCardHeight(
            for: targetPreset,
            shortSide: shortSide
        )

        // Paginate the content
        return paginateDocument(
            document: document,
            maxCardHeight: maxCardHeight
        )
    }

    /// Check if a document needs pagination
    /// - Parameter document: The document to check
    /// - Returns: True if pagination is recommended
    public static func needsPagination(
        for document: ShareImageDocument
    ) -> Bool {
        let selection = AutoPresetPicker.selectPreset(for: document)
        return selection.shouldPaginate
    }

    // MARK: - Private Helpers

    private static func paginateDocument(
        document: ShareImageDocument,
        maxCardHeight: CGFloat
    ) -> [Page] {
        var pages: [Page] = []
        let allComments = document.allComments

        // If no comments, just return single page with the post
        if allComments.isEmpty {
            return [Page(
                index: 0,
                totalPages: 1,
                document: document,
                preset: targetPreset
            )]
        }

        // Calculate approximate comments per page
        // Leave room for the post on page 1
        let postHeight = estimatePostHeight(document: document)
        let availableForCommentsPage1 = maxCardHeight - postHeight
        let availableForCommentsOtherPages = maxCardHeight - 100  // Just header margin

        let commentsPerPage1 = max(
            minCommentsPerPage,
            Int(availableForCommentsPage1 / estimatedCommentHeight)
        )
        let commentsPerOtherPages = max(
            minCommentsPerPage,
            Int(availableForCommentsOtherPages / estimatedCommentHeight)
        )

        // Slice comments into pages
        var remainingComments = allComments
        var pageIndex = 0

        // First page: includes the post
        let firstPageComments = Array(remainingComments.prefix(commentsPerPage1))
        remainingComments = Array(remainingComments.dropFirst(commentsPerPage1))

        let firstPageDoc = createPageDocument(
            from: document,
            comments: firstPageComments,
            includePost: true,
            isFirstPage: true
        )

        pages.append(Page(
            index: pageIndex,
            totalPages: 0,  // Will update later
            document: firstPageDoc,
            preset: targetPreset
        ))
        pageIndex += 1

        // Subsequent pages: comments only
        while !remainingComments.isEmpty {
            let pageComments = Array(remainingComments.prefix(commentsPerOtherPages))
            remainingComments = Array(remainingComments.dropFirst(commentsPerOtherPages))

            let pageDoc = createPageDocument(
                from: document,
                comments: pageComments,
                includePost: false,
                isFirstPage: false
            )

            pages.append(Page(
                index: pageIndex,
                totalPages: 0,  // Will update later
                document: pageDoc,
                preset: targetPreset
            ))
            pageIndex += 1
        }

        // Update total page counts
        let totalPages = pages.count
        pages = pages.map { page in
            Page(
                index: page.index,
                totalPages: totalPages,
                document: page.document,
                preset: page.preset
            )
        }

        return pages
    }

    private static func createPageDocument(
        from original: ShareImageDocument,
        comments: [CommentRenderable],
        includePost: Bool,
        isFirstPage: Bool
    ) -> ShareImageDocument {
        ShareImageDocument(
            selectedPost: original.selectedPost,
            selectedCommentID: original.selectedCommentID,
            ancestorChain: isFirstPage ? original.ancestorChain : [],
            replySubtree: comments,
            includePostDetails: includePost,
            hideUsernames: original.hideUsernames,
            showWatermark: original.showWatermark && isFirstPage,  // Watermark only on first page
            includeReplies: !comments.isEmpty
        )
    }

    private static func estimatePostHeight(document: ShareImageDocument) -> CGFloat {
        guard document.includePostDetails else { return 0 }

        var height: CGFloat = 150  // Base height for avatar, author, basic content

        // Add for content length
        let contentLength = document.selectedPost.content.characters.count
        let estimatedLines = max(1, contentLength / 50)
        height += CGFloat(estimatedLines) * 25

        // Add for media
        if !document.selectedPost.mediaThumbnails.isEmpty {
            height += 300
        }

        // Add for link preview
        if document.selectedPost.linkPreviewData != nil {
            height += 120
        }

        // Add for quote post
        if document.selectedPost.quotePostData != nil {
            height += 150
        }

        return height
    }
}
