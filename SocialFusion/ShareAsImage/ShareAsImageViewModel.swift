import Combine
import Foundation
import SwiftUI

@MainActor
public class ShareAsImageViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var previewImage: UIImage?
    @Published var isRendering = false
    @Published var isRefiningPreview = false
    @Published var renderingProgress: String = ""
    @Published var errorMessage: String?

    // Auto-selected preset and pagination
    @Published var autoSelectedPreset: ShareCanvasPreset?
    @Published var pageCount: Int = 1

    // Preview-driven configuration
    @Published var includeEarlier: Bool = false
    @Published var includeLater: Bool = false
    @Published var hideUsernames: Bool = false
    @Published var showWatermark: Bool = true

    // MARK: - Private Properties

    private let originalPost: Post
    private var currentThreadContext: ThreadContext?
    public let isReply: Bool  // Whether we're sharing a reply vs a post
    private var cancellables = Set<AnyCancellable>()
    private var previewTask: Task<Void, Never>?
    private var userMapping: [String: String] = [:]

    // MARK: - Initialization

    public init(
        post: Post,
        threadContext: ThreadContext?,
        isReply: Bool = false
    ) {
        self.originalPost = post
        self.currentThreadContext = threadContext
        self.isReply = isReply

        // Set defaults based on whether sharing a post or reply
        if isReply {
            // Reply: Earlier replies ON, Later replies OFF
            self.includeEarlier = true
            self.includeLater = false
        } else {
            // Post: Both OFF
            self.includeEarlier = false
            self.includeLater = false
        }

        // Debounce preview updates
        setupPreviewDebouncing()

        // Initial preview render - set loading state immediately
        isRendering = true
        renderingProgress = "Preparing..."
        Task {
            await updatePreview()
        }
    }

    // MARK: - Preview Updates

    private func setupPreviewDebouncing() {
        // Combine all configuration changes
        Publishers.CombineLatest4(
            $includeEarlier,
            $includeLater,
            $hideUsernames,
            $showWatermark
        )
        .dropFirst()
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updatePreview()
            }
        }
        .store(in: &cancellables)
    }

    private func updatePreview() async {
        previewTask?.cancel()

        previewTask = Task {
            isRendering = true
            isRefiningPreview = false
            errorMessage = nil
            renderingProgress = "Rendering preview..."

            // Build updated document with current config
            let updatedDocument = buildDocument()

            // Render immediately for responsive first paint (media may still be placeholders)
            let (image, preset) = ShareImageRenderer.renderAutoPreview(document: updatedDocument)

            if let image = image {
                if !Task.isCancelled {
                    // Update preset and page count
                    autoSelectedPreset = preset
                    let pages = ThreadPaginator.paginate(document: updatedDocument)
                    pageCount = pages.count

                    // Use withAnimation for smooth crossfade
                    withAnimation(.easeInOut(duration: 0.2)) {
                        previewImage = image
                    }
                }
            } else {
                if !Task.isCancelled {
                    errorMessage = "Failed to generate preview"
                }
            }

            isRendering = false

            if Task.isCancelled { return }

            // Continue warming media and refresh preview in the background
            isRefiningPreview = true
            renderingProgress = "Loading media..."
            await ShareImagePreloader.preloadImages(for: updatedDocument)

            if Task.isCancelled {
                isRefiningPreview = false
                renderingProgress = ""
                return
            }

            let (refinedImage, refinedPreset) = ShareImageRenderer.renderAutoPreview(document: updatedDocument)
            if let refinedImage = refinedImage {
                autoSelectedPreset = refinedPreset
                withAnimation(.easeInOut(duration: 0.2)) {
                    previewImage = refinedImage
                }
            }

            isRefiningPreview = false
            renderingProgress = ""
        }

        await previewTask?.value
    }

    public func updateThreadContext(_ threadContext: ThreadContext) {
        currentThreadContext = threadContext
        Task { @MainActor in
            await updatePreview()
        }
    }

    // MARK: - Export

    /// Export with auto-selected preset (returns all pages for multi-page exports)
    public func exportImages() async throws -> ShareExportResult {
        isRendering = true
        errorMessage = nil
        renderingProgress = "Preparing export..."
        defer {
            isRendering = false
            renderingProgress = ""
        }

        let document = buildDocument()

        // Pre-load images before rendering
        renderingProgress = "Loading images..."
        await ShareImagePreloader.preloadImages(for: document)

        renderingProgress = "Rendering image..."
        let result = try ShareImageRenderer.renderAutoExport(document: document)

        return result
    }

    /// Legacy export method for backward compatibility
    public func exportImage() async throws -> (image: UIImage, url: URL) {
        let result = try await exportImages()

        guard let image = result.image else {
            throw ShareImageRenderer.RenderError.failedToRender
        }

        renderingProgress = "Saving..."

        // Generate human-readable filename
        let filename = shareImageFilename(
            context: isReply ? .reply : (includeLater ? .thread : .post),
            authorHandle: hideUsernames ? nil : originalPost.authorUsername
        )

        let url = try ShareImageRenderer.saveToTempFile(image, filename: filename)

        return (image, url)
    }

    /// Export and save all pages, returning URLs
    public func exportAndSaveAll() async throws -> (images: [UIImage], urls: [URL]) {
        let result = try await exportImages()

        renderingProgress = "Saving..."

        let baseFilename = shareImageFilename(
            context: isReply ? .reply : (includeLater ? .thread : .post),
            authorHandle: hideUsernames ? nil : originalPost.authorUsername
        )

        let urls = try ShareImageRenderer.saveAllToTempFiles(result.images, baseFilename: baseFilename)

        return (result.images, urls)
    }

    // MARK: - Document Building

    private func buildDocument() -> ShareImageDocument {
        var mapping = userMapping

        let config = ShareImageConfig(
            includeEarlier: includeEarlier,
            includeLater: includeLater,
            hideUsernames: hideUsernames,
            showWatermark: showWatermark
        )

        let document: ShareImageDocument

        if isReply, let threadContext = currentThreadContext {
            // Building from a reply
            document = ShareThreadRenderBuilder.buildDocument(
                from: originalPost,
                threadContext: threadContext,
                config: config,
                userMapping: &mapping
            )
        } else {
            // Building from a post
            document = ShareThreadRenderBuilder.buildDocument(
                from: originalPost,
                threadContext: currentThreadContext,
                config: config,
                userMapping: &mapping
            )
        }

        userMapping = mapping
        return document
    }

    // MARK: - Filename Generation

    private func shareImageFilename(
        context: ShareContext,
        authorHandle: String?
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let date = formatter.string(from: Date())

        let contextPart: String = {
            switch context {
            case .post: return "Post"
            case .thread: return "Thread"
            case .reply: return "Reply"
            }
        }()

        let authorPart = authorHandle.map { " – \($0)" } ?? ""

        return "SocialFusion – \(contextPart)\(authorPart) – \(date).jpg"
    }

    private enum ShareContext {
        case post
        case thread
        case reply
    }
}
