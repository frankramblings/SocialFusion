import SwiftUI

/// A single skeleton placeholder card that mirrors the PostCardView layout.
/// The shimmer phase is passed in externally so all cards animate in sync.
struct SkeletonPostCard: View {
  let phase: CGFloat
  let reduceMotion: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Avatar placeholder
      Circle()
        .fill(shimmerFill)
        .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 8) {
        // Display name bar
        RoundedRectangle(cornerRadius: 4)
          .fill(shimmerFill)
          .frame(width: 120, height: 14)

        // Handle bar
        RoundedRectangle(cornerRadius: 4)
          .fill(shimmerFill)
          .frame(width: 80, height: 12)

        // Body text lines
        VStack(alignment: .leading, spacing: 6) {
          RoundedRectangle(cornerRadius: 4)
            .fill(shimmerFill)
            .frame(maxWidth: .infinity)
            .frame(height: 12)

          RoundedRectangle(cornerRadius: 4)
            .fill(shimmerFill)
            .frame(maxWidth: .infinity)
            .frame(height: 12)

          RoundedRectangle(cornerRadius: 4)
            .fill(shimmerFill)
            .frame(width: 180, height: 12)
        }
        .padding(.top, 2)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Loading post")
  }

  private var shimmerFill: some ShapeStyle {
    if reduceMotion {
      return AnyShapeStyle(Color.gray.opacity(0.15))
    }
    return AnyShapeStyle(
      LinearGradient(
        stops: [
          .init(color: Color.gray.opacity(0.1), location: phase - 0.3),
          .init(color: Color.gray.opacity(0.25), location: phase),
          .init(color: Color.gray.opacity(0.1), location: phase + 0.3),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
  }
}

/// Container that drives the shimmer phase for a stack of skeleton cards.
/// Uses `TimelineView` so all cards animate in perfect sync with a shared clock.
struct SkeletonTimelineView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Number of placeholder cards to display (capped at 6 for performance).
  var cardCount: Int = 5

  private var clampedCount: Int {
    min(max(cardCount, 1), 6)
  }

  var body: some View {
    if reduceMotion {
      staticContent
    } else {
      TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
        let elapsed = context.date.timeIntervalSinceReferenceDate
        let period: Double = 1.5
        let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period * 1.3)

        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(0..<clampedCount, id: \.self) { _ in
              SkeletonPostCard(phase: phase, reduceMotion: false)
              Divider()
            }
          }
        }
        .scrollDisabled(true)
      }
    }
  }

  private var staticContent: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(0..<clampedCount, id: \.self) { _ in
          SkeletonPostCard(phase: 0.5, reduceMotion: true)
          Divider()
        }
      }
    }
    .scrollDisabled(true)
  }
}

// MARK: - Preview
struct SkeletonPostCard_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      SkeletonTimelineView()
        .previewDisplayName("Shimmer")

      // Static (reduce motion) preview — uses direct card with reduceMotion flag
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(0..<5, id: \.self) { _ in
            SkeletonPostCard(phase: 0.5, reduceMotion: true)
            Divider()
          }
        }
      }
      .scrollDisabled(true)
      .previewDisplayName("Reduce Motion")
    }
  }
}
