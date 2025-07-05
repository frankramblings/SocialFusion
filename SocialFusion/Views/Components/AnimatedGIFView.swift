import ImageIO
import SwiftUI
import UIKit

/// A SwiftUI view that displays animated GIFs properly
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard let url = url else {
            uiView.image = nil
            return
        }

        // Load the GIF data
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                await MainActor.run {
                    // Create animated image from GIF data
                    if let animatedImage = UIImage.animatedImageWithData(data) {
                        uiView.image = animatedImage
                    } else {
                        // Fallback to static image if animation fails
                        uiView.image = UIImage(data: data)
                    }
                }
            } catch {
                print("❌ [AnimatedGIFView] Failed to load GIF from \(url): \(error)")
                await MainActor.run {
                    uiView.image = nil
                }
            }
        }
    }
}

extension UIImage {
    /// Create an animated UIImage from GIF data
    static func animatedImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var duration: TimeInterval = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                continue
            }

            // Get frame duration
            let frameDuration = getFrameDuration(from: source, at: i)
            duration += frameDuration

            let image = UIImage(cgImage: cgImage)
            images.append(image)
        }

        guard !images.isEmpty else {
            return nil
        }

        // Create animated image
        return UIImage.animatedImage(with: images, duration: duration)
    }

    private static func getFrameDuration(from source: CGImageSource, at index: Int) -> TimeInterval
    {
        let defaultDuration: TimeInterval = 0.1

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any]
        else {
            return defaultDuration
        }

        guard let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return defaultDuration
        }

        let unclampedDelayTime =
            gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval

        let duration = unclampedDelayTime ?? delayTime ?? defaultDuration

        // Ensure minimum duration for smooth animation
        return max(duration, 0.02)
    }
}

#Preview {
    AnimatedGIFView(url: URL(string: "https://media.giphy.com/media/3o7aD2saalBwwftBIY/giphy.gif"))
        .frame(width: 200, height: 200)
}
