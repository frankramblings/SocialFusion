import SwiftUI

/// A stable AsyncImage that prevents layout shifts by maintaining consistent dimensions
struct StabilizedAsyncImage: View {
    let idealHeight: CGFloat
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    let showLoadingState: Bool

    @State private var imageSize: CGSize = .zero
    @State private var hasLoaded = false

    // Stabilize the URL to prevent cancellation during view updates
    private let stableURL: URL?

    init(
        url: URL?,
        idealHeight: CGFloat = 200,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 12,
        showLoadingState: Bool = true
    ) {
        self.stableURL = url  // Capture URL at init time
        self.idealHeight = idealHeight
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.showLoadingState = showLoadingState
    }

    var body: some View {
        AsyncImage(url: stableURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: idealHeight)
                    .cornerRadius(cornerRadius)
                    .clipped()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hasLoaded = true
                        }
                    }

            case .failure(_):
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity, idealHeight: idealHeight)
                    .cornerRadius(cornerRadius)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    )

            case .empty:
                if showLoadingState {
                    StabilizedImageLoadingView(
                        height: idealHeight,
                        cornerRadius: cornerRadius
                    )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(maxWidth: .infinity, idealHeight: idealHeight)
                        .cornerRadius(cornerRadius)
                }

            @unknown default:
                EmptyView()
            }
        }
        .id(stableURL?.absoluteString ?? "no-url")  // Stable ID to prevent cancellation
        .animation(.easeInOut(duration: 0.2), value: hasLoaded)
    }
}

/// Loading state for stabilized images
private struct StabilizedImageLoadingView: View {
    let height: CGFloat
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.gray.opacity(0.1), location: phase - 0.3),
                        .init(color: Color.gray.opacity(0.3), location: phase),
                        .init(color: Color.gray.opacity(0.1), location: phase + 0.3),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(
                maxWidth: .infinity,
                idealHeight: height,
                maxHeight: height
            )
            .cornerRadius(cornerRadius)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

#Preview {
    VStack(spacing: 16) {
        StabilizedAsyncImage(
            url: URL(string: "https://picsum.photos/400/200"),
            idealHeight: 200
        )

        StabilizedAsyncImage(
            url: URL(string: "invalid-url"),
            idealHeight: 150
        )

        StabilizedAsyncImage(
            url: nil,
            idealHeight: 100
        )
    }
    .padding()
}
