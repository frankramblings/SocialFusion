import ImageIO
import SwiftUI
import UIKit

public struct GIFUnfurlContainer: View {
    let url: URL
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let showControls: Bool
    let onTap: (() -> Void)?

    @State private var animatedImage: UIImage?
    @State private var isLoading: Bool = false

    public init(
        url: URL,
        maxHeight: CGFloat,
        cornerRadius: CGFloat,
        showControls: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.url = url
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
        self.showControls = showControls
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if FeatureFlags.enableGIFUnfurling {
                ZStack {
                    if let animatedImage {
                        Image(uiImage: animatedImage)
                            .resizable()
                            .scaledToFit()
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
        .frame(maxHeight: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func loadIfNeeded() {
        guard FeatureFlags.enableGIFUnfurling, !isLoading, animatedImage == nil else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let unfurled = try await GIFUnfurlingService.shared.unfurl(url: url)
                if let image = Self.makeAnimatedImage(from: unfurled.data) {
                    animatedImage = image
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

