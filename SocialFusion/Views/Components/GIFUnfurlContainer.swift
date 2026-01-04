import ImageIO
import SwiftUI
import UIKit

/// Coordinator to isolate UIImage from SwiftUI's diffing
private class AnimatedImageCoordinator {
    var lastImageId: ObjectIdentifier?
    var imageView: UIImageView?
    
    func updateImage(_ image: UIImage, imageView: UIImageView, contentMode: UIView.ContentMode) {
        let imageId = ObjectIdentifier(image)
        
        // Only update if image has changed
        guard lastImageId != imageId else {
            // Image hasn't changed - ensure animation is still running if it's animated
            if imageView.isAnimating {
                return // Already animating, no need to restart
            }
            // If animation stopped, restart it for animated images
            if image.duration > 0, let frames = image.images, frames.count > 1 {
                imageView.animationImages = frames
                imageView.animationDuration = image.duration
                imageView.animationRepeatCount = 0 // Infinite loop
                imageView.image = nil
                imageView.startAnimating()
            }
            return
        }
        lastImageId = imageId
        
        imageView.contentMode = contentMode
        
        // Check if image is animated (has multiple frames)
        let isAnimated = image.duration > 0
        
        if isAnimated {
            // Use autoreleasepool and exception handling to safely access images array
            autoreleasepool {
                do {
                    // Wrap in do-catch to handle any C++ exceptions from accessing images array
                    var frames: [UIImage]? = nil
                    var frameCount = 0
                    
                    // Safely access images array with exception handling
                    try? autoreleasepool {
                        frames = image.images
                        frameCount = frames?.count ?? 0
                    }
                    
                    if let frames = frames, frameCount > 1 {
                        // Use frames array for animation
                        imageView.animationImages = frames
                        imageView.animationDuration = image.duration
                        imageView.animationRepeatCount = 0 // Infinite loop (0 = infinite)
                        imageView.image = nil // Clear static image when using animationImages
                        imageView.startAnimating() // Autoplay - start animation immediately
                    } else {
                        // Fallback: single frame or no frames array
                        imageView.animationImages = nil
                        imageView.image = image
                        imageView.stopAnimating()
                    }
                }
            }
        } else {
            // Static image
            imageView.animationImages = nil
            imageView.image = image
            imageView.stopAnimating()
        }
    }
}

/// UIViewRepresentable wrapper for animated UIImageView with proper container bounds
private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

    func makeCoordinator() -> AnimatedImageCoordinator {
        AnimatedImageCoordinator()
    }

    func makeUIView(context: Context) -> GIFContainerView {
        let containerView = GIFContainerView()
        containerView.clipsToBounds = true
        containerView.backgroundColor = UIColor.clear

        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(imageView)
        containerView.imageView = imageView
        context.coordinator.imageView = imageView

        // Use constraints for proper bounds handling
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // Let SwiftUI handle the overall sizing
        containerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        containerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        containerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        containerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Configure initial image and ensure animation starts immediately
        if let imageView = context.coordinator.imageView {
            context.coordinator.updateImage(image, imageView: imageView, contentMode: contentMode)
            // Double-check animation is running for animated GIFs (autoplay)
            if image.duration > 0, let frames = image.images, frames.count > 1, !imageView.isAnimating {
                imageView.animationImages = frames
                imageView.animationDuration = image.duration
                imageView.animationRepeatCount = 0 // Infinite loop
                imageView.image = nil
                imageView.startAnimating() // Ensure autoplay
            }
        }

        return containerView
    }

    func updateUIView(_ containerView: GIFContainerView, context: Context) {
        guard let imageView = containerView.imageView else { return }
        // Ensure coordinator has the latest imageView reference
        context.coordinator.imageView = imageView
        context.coordinator.updateImage(image, imageView: imageView, contentMode: contentMode)
    }
}

/// Custom container view that properly handles sizing for SwiftUI integration
private class GIFContainerView: UIView {
    var imageView: UIImageView?

    override var intrinsicContentSize: CGSize {
        // Return no intrinsic size - let SwiftUI decide
        return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Force clipping to container bounds - constraints handle the sizing
        self.clipsToBounds = true
    }
}

public struct GIFUnfurlContainer: View {
    let url: URL
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let showControls: Bool
    let contentMode: UIView.ContentMode
    let onTap: (() -> Void)?

    @State private var animatedImage: UIImage?
    @State private var isLoading: Bool = false
    @State private var imageAspectRatio: CGFloat?

    public init(
        url: URL,
        maxHeight: CGFloat,
        cornerRadius: CGFloat,
        showControls: Bool = true,
        contentMode: UIView.ContentMode = .scaleAspectFill,
        onTap: (() -> Void)? = nil
    ) {
        self.url = url
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.showControls = showControls
        self.contentMode = contentMode
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if FeatureFlags.enableGIFUnfurling {
                if let animatedImage, let aspectRatio = imageAspectRatio, aspectRatio > 0 {
                    // Use aspectRatio modifier for natural sizing - respects maxHeight without clipping
                    AnimatedImageView(image: animatedImage, contentMode: .scaleAspectFit)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: maxHeight > 0 ? maxHeight : nil)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?() }
                } else {
                    // Loading or no aspect ratio yet - use GeometryReader for dynamic sizing
                    GeometryReader { geometry in
                        ZStack {
                            if let animatedImage {
                                AnimatedImageView(image: animatedImage, contentMode: .scaleAspectFit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: calculatedHeight(for: geometry.size.width))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?() }
                    }
                    .frame(maxHeight: maxHeight > 0 ? maxHeight : nil)
                    .onAppear(perform: loadIfNeeded)
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .overlay(
                        Text("GIF unfurling disabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .onAppear(perform: loadIfNeeded)
    }
    
    private func calculatedHeight(for width: CGFloat) -> CGFloat {
        let targetWidth = width > 0 ? width : UIScreen.main.bounds.width - 76 // Fallback width (screen - typical padding)
        
        guard let aspectRatio = imageAspectRatio, targetWidth > 0, aspectRatio > 0 else {
            // Fallback to a reasonable aspect ratio while loading
            // Don't restrict to maxHeight during loading - let it calculate naturally
            return targetWidth / 1.5
        }
        // Calculate natural height based on aspect ratio - don't apply maxHeight here
        // The maxHeight constraint on the frame will handle limiting, allowing proper aspect ratio
        let calculatedHeight = targetWidth / aspectRatio
        // Return the natural calculated height - the frame(maxHeight:) constraint will limit it
        // This prevents the "arbitrary sliver" clipping issue
        return calculatedHeight
    }

    private func loadIfNeeded() {
        guard FeatureFlags.enableGIFUnfurling, !isLoading, animatedImage == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let unfurled = try await GIFUnfurlingService.shared.unfurl(url: url)
                if let image = Self.makeAnimatedImage(from: unfurled.data) {
                    await MainActor.run {
                        animatedImage = image
                        // Calculate aspect ratio to eliminate empty space
                        let size = image.size
                        if size.height > 0 {
                            imageAspectRatio = size.width / size.height
                        }
                    }
                }
            } catch {
                // Keep placeholder; remain silent to avoid log noise in production
            }
        }
    }

    private static func makeAnimatedImage(from data: Data) -> UIImage? {
        // Use autoreleasepool to manage memory and prevent crashes
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let count = CGImageSourceGetCount(source)
            var frames: [UIImage] = []
            var duration: Double = 0
            
            // Process frames in autoreleasepool to prevent memory issues
            for i in 0..<count {
                autoreleasepool {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { return }
                    let frameDuration = frameDuration(from: source, at: i)
                    duration += frameDuration
                    frames.append(UIImage(cgImage: cgImage))
                }
            }
            
            guard !frames.isEmpty else { return nil }
            // Create animated image - this is safe as long as we use coordinator pattern for display
            return UIImage.animatedImage(with: frames, duration: duration)
        }
    }

    private static func frameDuration(from source: CGImageSource, at index: Int) -> Double {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as NSDictionary?,
            let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? NSDictionary,
            let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? NSNumber
        else { return 0.1 }
        return delay.doubleValue
    }
}
