import SwiftUI
import UIKit

/// Renders share image views to PNG files
@MainActor
public struct ShareImageRenderer {

    public struct RenderConfig {
        public let shortSide: CGFloat
        public let previewShortSide: CGFloat

        // Legacy properties for backward compatibility
        public var targetPixelWidth: CGFloat { shortSide }
        public var maxPixelHeight: CGFloat { shortSide * 2 }
        public var previewPixelWidth: CGFloat { previewShortSide }

        public init(
            shortSide: CGFloat = 1080,
            previewShortSide: CGFloat = 400
        ) {
            self.shortSide = shortSide
            self.previewShortSide = previewShortSide
        }

        // Legacy initializer for backward compatibility
        public init(
            targetPixelWidth: CGFloat = 1080,
            maxPixelHeight: CGFloat = 3000,
            previewPixelWidth: CGFloat = 640
        ) {
            self.shortSide = targetPixelWidth
            self.previewShortSide = previewPixelWidth * 0.625  // Scale down
        }
    }
    
    // MARK: - Auto-Preset Preview

    /// Renders a preview with auto-selected preset
    public static func renderAutoPreview(
        document: ShareImageDocument,
        config: RenderConfig = RenderConfig()
    ) -> (image: UIImage?, preset: ShareCanvasPreset) {
        let selection = AutoPresetPicker.selectPreset(for: document)
        let preset = selection.preset

        let view = ShareCanvasView(
            document: document,
            preset: preset,
            shortSide: config.previewShortSide
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale

        return (renderer.uiImage, preset)
    }

    // MARK: - Auto-Preset Export

    /// Renders export images with auto-selected preset, handling pagination
    public static func renderAutoExport(
        document: ShareImageDocument,
        config: RenderConfig = RenderConfig()
    ) throws -> ShareExportResult {
        // Get pages (handles pagination automatically)
        let pages = ThreadPaginator.paginate(document: document)

        var images: [UIImage] = []
        var preset: ShareCanvasPreset = .ratio9x16

        for page in pages {
            preset = page.preset

            let view = ShareCanvasView(
                document: page.document,
                preset: page.preset,
                shortSide: config.shortSide
            )

            let renderer = ImageRenderer(content: view)
            renderer.scale = UIScreen.main.scale

            guard let image = renderer.uiImage else {
                throw RenderError.failedToRender
            }

            images.append(image)
        }

        return ShareExportResult(images: images, preset: preset)
    }

    // MARK: - Legacy Preview Render

    /// Renders a preview image at lower resolution (legacy, no canvas background)
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
    
    // MARK: - Legacy Export Render

    /// Renders a full-resolution export image (legacy, no canvas background)
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

    /// Saves multiple images to temp files and returns URLs
    public static func saveAllToTempFiles(
        _ images: [UIImage],
        baseFilename: String
    ) throws -> [URL] {
        var urls: [URL] = []

        for (index, image) in images.enumerated() {
            let filename: String
            if images.count == 1 {
                filename = baseFilename
            } else {
                // Insert page number before extension
                let components = baseFilename.components(separatedBy: ".")
                if components.count >= 2 {
                    let name = components.dropLast().joined(separator: ".")
                    let ext = components.last!
                    filename = "\(name) - Page \(index + 1).\(ext)"
                } else {
                    filename = "\(baseFilename) - Page \(index + 1)"
                }
            }

            let url = try saveToTempFile(image, filename: filename)
            urls.append(url)
        }

        return urls
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
