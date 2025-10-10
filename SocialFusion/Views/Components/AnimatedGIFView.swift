import ImageIO
import SwiftUI
import UIKit

/// A SwiftUI view that displays animated GIFs properly with accessibility support
struct AnimatedGIFView: View {
    let url: URL?

    var body: some View {
        AnimatedGIFViewRepresentable(url: url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Animated GIF")
            .accessibilityHint("This is an animated image that plays automatically")
            .accessibilityAddTraits([.playsSound])
    }
}

/// Internal UIViewRepresentable for GIF display
private struct AnimatedGIFViewRepresentable: UIViewRepresentable {
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

// Using shared UIImage.animatedImageWithData implementation from SmartMediaView

#Preview {
    AnimatedGIFView(url: URL(string: "https://media.giphy.com/media/3o7aD2saalBwwftBIY/giphy.gif"))
        .frame(width: 200, height: 200)
}
