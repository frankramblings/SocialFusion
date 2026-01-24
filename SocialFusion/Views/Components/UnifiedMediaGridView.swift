import SwiftUI

// MARK: - Frame Tracking for Hero Eligibility

/// PreferenceKey to track thumbnail frames for hero transition eligibility
/// CRITICAL FIX: Custom reduce function that only updates when frames change significantly
private struct ThumbnailFramePreference: PreferenceKey {
    static var defaultValue: [String: ThumbnailFrameInfo] = [:]

    static func reduce(
        value: inout [String: ThumbnailFrameInfo], nextValue: () -> [String: ThumbnailFrameInfo]
    ) {
        let newValues = nextValue()
        // CRITICAL FIX: Only merge if frames changed significantly (more than 5 points)
        // This prevents "Bound preference tried to update multiple times per frame" warnings
        for (id, newFrameInfo) in newValues {
            if let oldFrameInfo = value[id] {
                let frameChanged = abs(newFrameInfo.frame.origin.x - oldFrameInfo.frame.origin.x) > 5 ||
                                  abs(newFrameInfo.frame.origin.y - oldFrameInfo.frame.origin.y) > 5 ||
                                  abs(newFrameInfo.frame.width - oldFrameInfo.frame.width) > 5 ||
                                  abs(newFrameInfo.frame.height - oldFrameInfo.frame.height) > 5
                if frameChanged {
                    value[id] = newFrameInfo
                }
            } else {
                // Always add new entries
                value[id] = newFrameInfo
            }
        }
    }
}

/// Frame information with timestamp for staleness detection
struct ThumbnailFrameInfo: Equatable {
    let frame: CGRect
    let timestamp: Date

    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 0.4  // Consider stale after 400ms
    }

    static func == (lhs: ThumbnailFrameInfo, rhs: ThumbnailFrameInfo) -> Bool {
        // Compare frames and timestamps for equality
        lhs.frame == rhs.frame && abs(lhs.timestamp.timeIntervalSince(rhs.timestamp)) < 0.1
    }
}

/// Helper view that tracks frame changes and only updates preference when frame changes significantly
/// CRITICAL FIX: Prevents "Bound preference ThumbnailFramePreference tried to update multiple times per frame" warnings
/// The PreferenceKey's reduce function now handles filtering, so we can set preference every frame
private struct FrameTrackingView: View {
    let attachmentID: String
    let threshold: CGFloat  // Not used anymore, but kept for compatibility
    
    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            
            // CRITICAL FIX: Set preference every frame, but PreferenceKey.reduce will filter
            // This prevents "Bound preference tried to update multiple times per frame" warnings
            Color.clear
                .preference(
                    key: ThumbnailFramePreference.self,
                    value: frame.width > 0 && frame.height > 0 ? [
                        attachmentID: ThumbnailFrameInfo(
                            frame: frame,
                            timestamp: Date()
                        )
                    ] : [:]
                )
        }
    }
}

struct UnifiedMediaGridView: View {
    let attachments: [Post.Attachment]
    var maxHeight: CGFloat = 600  // Increased from 300 to allow taller media

    // Use coordinator for fullscreen presentation
    @EnvironmentObject private var mediaCoordinator: FullscreenMediaCoordinator

    // Hero transition namespace - must be in same view hierarchy
    @Namespace private var mediaNamespace

    // Frame tracking for hero eligibility
    @State private var thumbnailFrames: [String: ThumbnailFrameInfo] = [:]
    @State private var preferenceUpdateTask: Task<Void, Never>?
    @State private var isUpdatingFrames = false

    var body: some View {
        Group {
            switch attachments.count {
            case 0:
                EmptyView()
            case 1:
                // For single GIFs, use a more permissive maxHeight to avoid cutting them off
                // Balance: Allow taller GIFs but cap at reasonable maximum
                let gifMaxHeight = attachments[0].type == .animatedGIF 
                    ? min(UIScreen.main.bounds.height * 0.75, 800)  // Balanced height for GIFs
                    : maxHeight
                SingleImageView(
                    attachment: attachments[0],
                    maxHeight: gifMaxHeight,
                    mediaNamespace: mediaNamespace,
                    isFullscreenPresented: mediaCoordinator.showFullscreen,
                    selectedAttachmentID: mediaCoordinator.selectedMedia?.id,
                    onTap: {
                        mediaCoordinator.present(
                            media: attachments[0],
                            allMedia: attachments,
                            showAltTextInitially: false,
                            mediaNamespace: mediaNamespace,
                            thumbnailFrames: thumbnailFrames
                        )
                    },
                    onAltTap: { att in
                        mediaCoordinator.present(
                            media: att,
                            allMedia: attachments,
                            showAltTextInitially: true,
                            mediaNamespace: mediaNamespace,
                            thumbnailFrames: thumbnailFrames
                        )
                    }
                )
                .frame(maxWidth: .infinity)
                .clipped()
            case 2...4:
                MultiImageGridView(
                    attachments: attachments,
                    mediaNamespace: mediaNamespace,
                    isFullscreenPresented: mediaCoordinator.showFullscreen,
                    selectedAttachmentID: mediaCoordinator.selectedMedia?.id,
                    onTap: { att in
                        mediaCoordinator.present(
                            media: att,
                            allMedia: attachments,
                            showAltTextInitially: false,
                            mediaNamespace: mediaNamespace,
                            thumbnailFrames: thumbnailFrames
                        )
                    },
                    onAltTap: { att in
                        mediaCoordinator.present(
                            media: att,
                            allMedia: attachments,
                            showAltTextInitially: true,
                            mediaNamespace: mediaNamespace,
                            thumbnailFrames: thumbnailFrames
                        )
                    }
                )
                .frame(maxWidth: .infinity)
                .clipped()
            default:
                MultiImageGridView(
                    attachments: Array(attachments.prefix(4)),
                    mediaNamespace: mediaNamespace,
                    isFullscreenPresented: mediaCoordinator.showFullscreen,
                    selectedAttachmentID: mediaCoordinator.selectedMedia?.id,
                    onTap: { att in
                        mediaCoordinator.present(
                            media: att,
                            allMedia: attachments,
                            showAltTextInitially: false,
                            mediaNamespace: mediaNamespace,
                            thumbnailFrames: thumbnailFrames
                        )
                    },
                    onAltTap: { att in
                        mediaCoordinator.present(
                            media: att,
                            allMedia: attachments,
                            showAltTextInitially: true,
                            mediaNamespace: mediaNamespace,
                            thumbnailFrames: thumbnailFrames
                        )
                    },
                    extraCount: attachments.count - 4
                )
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
        .onPreferenceChange(ThumbnailFramePreference.self) { frames in
            // Prevent updates if we're already updating to avoid multiple updates per frame
            guard !isUpdatingFrames else { return }
            
            // Cancel previous update task to debounce/throttle updates
            preferenceUpdateTask?.cancel()
            
            // Only update if frames actually changed significantly
            let hasSignificantChanges = frames.contains { (id, newFrame) in
                guard let oldFrame = thumbnailFrames[id] else { return true }
                // Only update if frame moved significantly (> 10 points) - increased threshold
                let frameChanged = abs(newFrame.frame.origin.x - oldFrame.frame.origin.x) > 10 ||
                                   abs(newFrame.frame.origin.y - oldFrame.frame.origin.y) > 10 ||
                                   abs(newFrame.frame.width - oldFrame.frame.width) > 10 ||
                                   abs(newFrame.frame.height - oldFrame.frame.height) > 10
                // Also update if timestamp is significantly different (newer frame) - increased threshold
                let timestampChanged = abs(newFrame.timestamp.timeIntervalSince(oldFrame.timestamp)) > 0.2
                return frameChanged || timestampChanged
            }
            
            guard hasSignificantChanges else { return }
            
            // Mark as updating to prevent concurrent updates
            isUpdatingFrames = true
            
            // Defer state update to prevent "Publishing changes from within view updates" warning
            // Use longer delay to throttle updates and prevent multiple updates per frame
            preferenceUpdateTask = Task { @MainActor in
                // Throttle to ~10fps (100ms) to prevent multiple updates per frame - even more aggressive throttling
                try? await Task.sleep(nanoseconds: 100_000_000) // ~6 frames at 60fps
                guard !Task.isCancelled else { 
                    isUpdatingFrames = false
                    return 
                }
                // Final check to ensure we're not updating during view rendering
                // Use DispatchQueue with an additional delay to ensure we're outside the current view update cycle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { // One more frame delay
                    guard !Task.isCancelled else { 
                        isUpdatingFrames = false
                        return 
                    }
                    thumbnailFrames = frames
                    isUpdatingFrames = false
                }
            }
        }
        .onDisappear {
            preferenceUpdateTask?.cancel()
        }
    }

    // Helper to check if hero transition is eligible for an attachment
    private func isHeroEligible(for attachmentID: String) -> Bool {
        guard let frameInfo = thumbnailFrames[attachmentID] else { return false }
        return !frameInfo.isStale && frameInfo.frame.width > 0 && frameInfo.frame.height > 0
    }
}

// MARK: - Fullscreen Overlay Component (for root-level presentation)

/// Fullscreen media overlay presented at root level to avoid clipping issues
struct FullscreenMediaOverlay: View {
    let media: Post.Attachment
    let allMedia: [Post.Attachment]
    let showAltTextInitially: Bool
    let mediaNamespace: Namespace.ID?
    let thumbnailFrames: [String: ThumbnailFrameInfo]
    @Binding var dismissalDirection: CGSize
    let onDismiss: () -> Void
    
    // Unique presentation ID - created once per presentation
    @State private var presentationID = UUID()

    var body: some View {
        ZStack {
            // Full black background covering entire screen
            Color.black
                .ignoresSafeArea(.all)

            // Fullscreen media view
            FullscreenMediaView(
                media: media,
                allMedia: allMedia,
                showAltTextInitially: showAltTextInitially,
                onDismiss: onDismiss
            )
            .id(presentationID) // Unique ID per presentation to ensure fresh state
        }
        .ignoresSafeArea(.all)
        .allowsHitTesting(true)
    }
}

private struct SingleImageView: View {
    let attachment: Post.Attachment
    var maxHeight: CGFloat = 600  // Increased from 500 to allow taller media
    let mediaNamespace: Namespace.ID
    let isFullscreenPresented: Bool
    let selectedAttachmentID: String?
    let onTap: () -> Void
    let onAltTap: ((Post.Attachment) -> Void)?

    // Capture stable URL at init time
    private let stableURL: URL?

    private var heroID: String {
        "media-\(attachment.id)"
    }

    private var isSelected: Bool {
        selectedAttachmentID == attachment.id && isFullscreenPresented
    }

    init(
        attachment: Post.Attachment,
        maxHeight: CGFloat = 500,
        mediaNamespace: Namespace.ID,
        isFullscreenPresented: Bool,
        selectedAttachmentID: String?,
        onTap: @escaping () -> Void,
        onAltTap: ((Post.Attachment) -> Void)? = nil
    ) {
        self.attachment = attachment
        self.maxHeight = maxHeight
        self.mediaNamespace = mediaNamespace
        self.isFullscreenPresented = isFullscreenPresented
        self.selectedAttachmentID = selectedAttachmentID
        self.onTap = onTap
        self.onAltTap = onAltTap
        self.stableURL = URL(string: attachment.url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Show placeholder when this thumbnail is selected (to avoid duplicate during transition)
            if isSelected {
                // Placeholder maintains layout space
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: maxHeight)
                    .shadow(
                        color: MediaConstants.Visual.shadowColor,
                        radius: MediaConstants.Visual.shadowRadius,
                        x: 0,
                        y: MediaConstants.Visual.shadowY
                    )
            } else {
                // Actual thumbnail with matchedGeometryEffect
                // ZERO LAYOUT SHIFT: Pass stableAspectRatio to prevent height changes after load
                SmartMediaView(
                    attachment: attachment,
                    contentMode: .fit,
                    maxWidth: .infinity,
                    maxHeight: maxHeight,
                    cornerRadius: MediaConstants.CornerRadius.feed,
                    heroID: heroID,
                    mediaNamespace: mediaNamespace,
                    stableAspectRatio: attachment.stableAspectRatio,  // Prevents layout shift
                    onTap: onTap
                )
                .background(
                    FrameTrackingView(
                        attachmentID: attachment.id,
                        threshold: 5.0  // Only update if frame moved more than 5 points
                    )
                )
                .shadow(
                    color: MediaConstants.Visual.shadowColor,
                    radius: MediaConstants.Visual.shadowRadius,
                    x: 0,
                    y: MediaConstants.Visual.shadowY
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous
                    )
                    .stroke(
                        Color.primary.opacity(MediaConstants.Visual.borderOpacity),
                        lineWidth: MediaConstants.Visual.borderWidth)
                )
            }

            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
                    .padding(.bottom, MediaConstants.Spacing.altBadgeVertical)
                    .padding(.trailing, MediaConstants.Spacing.altBadgeHorizontal)
                    .onTapGesture {
                        onAltTap?(attachment)
                    }
            }
        }
    }
}

private struct MultiImageGridView: View {
    let attachments: [Post.Attachment]
    let mediaNamespace: Namespace.ID
    let isFullscreenPresented: Bool
    let selectedAttachmentID: String?
    let onTap: (Post.Attachment) -> Void
    let onAltTap: ((Post.Attachment) -> Void)?
    var extraCount: Int = 0
    private let gridSize: CGFloat = 150
    private let spacing: CGFloat = MediaConstants.Spacing.grid  // Standardized to 4px

    var body: some View {
        HStack {
            Spacer()

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: spacing),
                    GridItem(.flexible()),
                ],
                spacing: spacing
            ) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    GridImageView(
                        attachment: attachment,
                        gridSize: gridSize,
                        mediaNamespace: mediaNamespace,
                        isFullscreenPresented: isFullscreenPresented,
                        selectedAttachmentID: selectedAttachmentID,
                        onTap: onTap,
                        extraCount: extraCount,
                        isLast: attachment.id == attachments.last?.id,
                        onAltTap: onAltTap
                    )
                }
            }
            .frame(maxWidth: gridSize * 2 + spacing)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GridImageView: View {
    let attachment: Post.Attachment
    let gridSize: CGFloat
    let mediaNamespace: Namespace.ID
    let isFullscreenPresented: Bool
    let selectedAttachmentID: String?
    let onTap: (Post.Attachment) -> Void
    let extraCount: Int
    let isLast: Bool
    let onAltTap: ((Post.Attachment) -> Void)?

    // Capture stable URL at init time
    private let stableURL: URL?

    private var heroID: String {
        "media-\(attachment.id)"
    }

    private var isSelected: Bool {
        selectedAttachmentID == attachment.id && isFullscreenPresented
    }

    init(
        attachment: Post.Attachment,
        gridSize: CGFloat,
        mediaNamespace: Namespace.ID,
        isFullscreenPresented: Bool,
        selectedAttachmentID: String?,
        onTap: @escaping (Post.Attachment) -> Void,
        extraCount: Int,
        isLast: Bool,
        onAltTap: ((Post.Attachment) -> Void)? = nil
    ) {
        self.attachment = attachment
        self.gridSize = gridSize
        self.mediaNamespace = mediaNamespace
        self.isFullscreenPresented = isFullscreenPresented
        self.selectedAttachmentID = selectedAttachmentID
        self.onTap = onTap
        self.extraCount = extraCount
        self.isLast = isLast
        self.onAltTap = onAltTap
        self.stableURL = URL(string: attachment.url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Show placeholder when this thumbnail is selected (to avoid duplicate during transition)
            if isSelected {
                // Placeholder maintains layout space
                RoundedRectangle(cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: gridSize, height: gridSize)
                    .shadow(
                        color: MediaConstants.Visual.shadowColor,
                        radius: MediaConstants.Visual.shadowRadius,
                        x: 0,
                        y: MediaConstants.Visual.shadowY
                    )
            } else {
                // Actual thumbnail with matchedGeometryEffect
                // Grid items have fixed size, but pass stableAspectRatio for internal rendering consistency
                SmartMediaView(
                    attachment: attachment,
                    contentMode: SmartMediaView.ContentMode.fill,
                    maxWidth: gridSize,
                    maxHeight: gridSize,
                    cornerRadius: MediaConstants.CornerRadius.feed,
                    heroID: heroID,
                    mediaNamespace: mediaNamespace,
                    stableAspectRatio: attachment.stableAspectRatio,
                    onTap: { onTap(attachment) }
                )
                .background(
                    FrameTrackingView(
                        attachmentID: attachment.id,
                        threshold: 5.0  // Only update if frame moved more than 5 points
                    )
                )
                .frame(width: gridSize, height: gridSize)
                .clipped()
                .shadow(
                    color: MediaConstants.Visual.shadowColor,
                    radius: MediaConstants.Visual.shadowRadius,
                    x: 0,
                    y: MediaConstants.Visual.shadowY
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous
                    )
                    .stroke(
                        Color.primary.opacity(MediaConstants.Visual.borderOpacity),
                        lineWidth: MediaConstants.Visual.borderWidth)
                )
            }

            if let alt = attachment.altText, !alt.isEmpty {
                GlassyAltBadge()
                    .padding(.bottom, MediaConstants.Spacing.altBadgeVertical)
                    .padding(.trailing, MediaConstants.Spacing.altBadgeHorizontal)
                    .onTapGesture {
                        onAltTap?(attachment)
                    }
            }

            // Show "+X more" overlay on the last item if there are extra items
            if extraCount > 0 && isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: gridSize, height: gridSize)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MediaConstants.CornerRadius.feed, style: .continuous)
                    )
                    .overlay(
                        Text("+\(extraCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// Helper badge for alt text indication with enhanced visibility
private struct GlassyAltBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("ALT")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1.5)
        .environment(\.colorScheme, .dark)  // Force dark appearance for glass effect
    }
}
