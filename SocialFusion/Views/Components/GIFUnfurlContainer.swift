import ImageIO
import SwiftUI
import UIKit

/// UIViewRepresentable wrapper for animated UIImageView with proper container bounds
private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

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

        return containerView
    }

    func updateUIView(_ containerView: GIFContainerView, context: Context) {
        containerView.imageView?.image = image
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
        GeometryReader { geometry in
            Group {
                if FeatureFlags.enableGIFUnfurling {
                    ZStack {
                        if let animatedImage {
                            AnimatedImageView(image: animatedImage, contentMode: .scaleAspectFit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ProgressView()
                        }
                    }
                    .onAppear(perform: loadIfNeeded)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .overlay(
                            Text("GIF unfurling disabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: calculatedHeight(for: geometry.size.width))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
        }
        .frame(maxHeight: maxHeight)
    }
    
    private func calculatedHeight(for width: CGFloat) -> CGFloat {
        guard let aspectRatio = imageAspectRatio, width > 0, aspectRatio > 0 else {
            // Fallback to a reasonable aspect ratio while loading
            return min(width / 1.5, maxHeight)
        }
        let calculatedHeight = width / aspectRatio
        return min(calculatedHeight, maxHeight)
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let frameDuration = frameDuration(from: source, at: i)
            duration += frameDuration
            frames.append(UIImage(cgImage: cgImage))
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
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
