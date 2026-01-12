import SwiftUI
import UIKit
import Combine

/// Synchronous image view that uses cached images and never fails
struct ShareSynchronousImageView: View {
    let url: URL?
    let placeholder: () -> AnyView
    let scale: CGFloat
    
    init(url: URL?, scale: CGFloat = 1.0, @ViewBuilder placeholder: @escaping () -> AnyView) {
        self.url = url
        self.scale = scale
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let url = url, let image = ImageCache.shared.getCachedImage(for: url) {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
            }
        }
    }
}

/// Synchronous avatar view that never fails
struct ShareSynchronousAvatarView: View {
    let url: URL?
    let size: CGFloat
    let scale: CGFloat
    
    init(url: URL?, size: CGFloat = 40, scale: CGFloat = 1.0) {
        self.url = url
        self.size = size
        self.scale = scale
    }
    
    var body: some View {
        ShareSynchronousImageView(url: url, scale: scale) {
            AnyView(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.secondary.opacity(0.3),
                                Color.secondary.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * scale, height: size * scale)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: (size * 0.5) * scale))
                            .foregroundColor(.secondary.opacity(0.6))
                    )
            )
        }
        .frame(width: size * scale, height: size * scale)
        .clipShape(Circle())
    }
}
