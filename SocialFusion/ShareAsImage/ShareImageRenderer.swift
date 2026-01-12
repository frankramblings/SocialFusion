import SwiftUI
import UIKit

/// Renders share image views to PNG files
@MainActor
public struct ShareImageRenderer {
    
    public struct RenderConfig {
        public let targetPixelWidth: CGFloat
        public let maxPixelHeight: CGFloat
        public let previewPixelWidth: CGFloat
        
        public init(
            targetPixelWidth: CGFloat = 1080,
            maxPixelHeight: CGFloat = 3000,
            previewPixelWidth: CGFloat = 640
        ) {
            self.targetPixelWidth = targetPixelWidth
            self.maxPixelHeight = maxPixelHeight
            self.previewPixelWidth = previewPixelWidth
        }
    }
    
    // MARK: - Preview Render
    
    /// Renders a preview image at lower resolution
    public static func renderPreview(
        document: ShareImageDocument,
        config: RenderConfig = RenderConfig()
    ) -> UIImage? {
        let view = ShareImageRootView(
            document: document,
            targetPixelWidth: config.previewPixelWidth
        )
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        
        return renderer.uiImage
    }
    
    // MARK: - Export Render
    
    /// Renders a full-resolution export image
    public static func renderExport(
        document: ShareImageDocument,
        config: RenderConfig = RenderConfig()
    ) throws -> UIImage {
        // Apply height guardrails if needed
        let adjustedDocument = applyHeightGuardrails(
            document: document,
            config: config
        )
        
        let view = ShareImageRootView(
            document: adjustedDocument,
            targetPixelWidth: config.targetPixelWidth
        )
        
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        
        guard let image = renderer.uiImage else {
            throw RenderError.failedToRender
        }
        
        // Check height
        let height = image.size.height
        if height > config.maxPixelHeight {
            // Apply stricter limits and retry
            let stricterDocument = applyStricterLimits(
                document: adjustedDocument,
                maxHeight: config.maxPixelHeight
            )
            
            let stricterView = ShareImageRootView(
                document: stricterDocument,
                targetPixelWidth: config.targetPixelWidth
            )
            
            let stricterRenderer = ImageRenderer(content: stricterView)
            stricterRenderer.scale = UIScreen.main.scale
            
            guard let finalImage = stricterRenderer.uiImage else {
                throw RenderError.failedToRender
            }
            
            return finalImage
        }
        
        return image
    }
    
    // MARK: - Save to File
    
    /// Saves the rendered image to a temporary file and returns the URL
    public static func saveToTempFile(_ image: UIImage, filename: String) throws -> URL {
        guard let data = image.pngData() else {
            throw RenderError.failedToEncode
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    // MARK: - Height Guardrails
    
    private static func applyHeightGuardrails(
        document: ShareImageDocument,
        config: RenderConfig
    ) -> ShareImageDocument {
        // For MVP, return as-is
        // Future: could trim comments or reduce line limits here
        return document
    }
    
    private static func applyStricterLimits(
        document: ShareImageDocument,
        maxHeight: CGFloat
    ) -> ShareImageDocument {
        // Reduce reply count if image is too tall
        let maxReplies = min(document.replySubtree.count, 20)
        let trimmedReplies = Array(document.replySubtree.prefix(maxReplies))
        
        return ShareImageDocument(
            selectedPost: document.selectedPost,
            selectedCommentID: document.selectedCommentID,
            ancestorChain: document.ancestorChain,
            replySubtree: trimmedReplies,
            includePostDetails: document.includePostDetails,
            hideUsernames: document.hideUsernames,
            showWatermark: document.showWatermark,
            includeReplies: document.includeReplies
        )
    }
    
    // MARK: - Errors
    
    public enum RenderError: LocalizedError {
        case failedToRender
        case failedToEncode
        
        public var errorDescription: String? {
            switch self {
            case .failedToRender:
                return "Failed to render share image"
            case .failedToEncode:
                return "Failed to encode image as PNG"
            }
        }
    }
}
