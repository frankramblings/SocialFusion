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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    // Drop the scale-in on Reduce Motion — the
                    // fade-in alone communicates "image arrived"
                    // without the subtle pop that the setting is
                    // meant to suppress.
                    .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.95)))
                    .onAppear {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            hasLoaded = true
                        }
                    }

            case .failure(_):
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity, idealHeight: idealHeight)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(Color(.systemGray2).gradient)
                            .symbolRenderingMode(.hierarchical)
                    )

            case .empty:
                if showLoadingState {
                    StabilizedImageLoadingView(
                        height: idealHeight,
                        cornerRadius: cornerRadius
                    )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(maxWidth: .infinity, idealHeight: idealHeight)
                }

            @unknown default:
                EmptyView()
            }
        }
        .id(stableURL?.absoluteString ?? "no-url")  // Stable ID to prevent cancellation
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hasLoaded)
    }
}

/// Loading state for stabilized images.
///
/// Drives the shimmer phase via TimelineView so all visible image
/// skeletons pulse in perfect sync against the system clock — and
/// to avoid AttributeGraph cycles that the older
/// `withAnimation(.repeatForever)` + `@State phase` pattern can
/// trigger when used inside other view updates. Matches the
/// SkeletonPostCard + StabilizedLinkPreview shimmer pattern.
private struct StabilizedImageLoadingView: View {
    let height: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Static fallback — same band of color, no motion.
                Rectangle().fill(Color(.systemGray5))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let period: Double = 1.5
                    let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period * 1.3)
                    Rectangle().fill(shimmerGradient(phase: phase))
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            idealHeight: height,
            maxHeight: height
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func shimmerGradient(phase: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(.systemGray5).opacity(0.6), location: phase - 0.3),
                .init(color: Color(.systemGray4), location: phase),
                .init(color: Color(.systemGray5).opacity(0.6), location: phase + 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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
