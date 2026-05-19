import SwiftUI

/// A pill-shaped chip indicating a profile is part of a merged identity.
///
/// Visually rhymes with the Fuse glyph: same purple/blue/cyan brand palette
/// from `LaunchAnimationView`. Tap target surfaces the unmerge / inspect
/// options; the chip itself is just visual indication.
///
/// Tappable: the parent supplies an `onTap` closure to present the unmerge
/// menu or details sheet.
public struct MergedIdentityChip: View {
    public let provenance: MergeProvenance
    public var onTap: (() -> Void)?

    private let purple = Color(red: 0.54, green: 0.39, blue: 1.00)
    private let blue = Color(red: 0.00, green: 0.59, blue: 1.00)
    private let cyan = Color(red: 0.11, green: 0.91, blue: 1.00)

    public init(provenance: MergeProvenance, onTap: (() -> Void)? = nil) {
        self.provenance = provenance
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let onTap = onTap {
                // Interactive variant: Button so the standard tap target,
                // double-tap-to-activate VoiceOver behavior, and pressed
                // state all come for free.
                Button(action: onTap) {
                    chipBody
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manages this merge.")
            } else {
                // Decorative variant: plain non-interactive group so
                // VoiceOver doesn't announce it as a button when there's
                // no action behind it.
                chipBody
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var chipBody: some View {
        HStack(spacing: 4) {
            miniGlyph
            Text("Merged identity")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [purple.opacity(0.85), blue.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    private var miniGlyph: some View {
        ZStack {
            Circle().fill(purple).frame(width: 8, height: 8).offset(x: -2)
            Circle().fill(blue).frame(width: 8, height: 8).offset(x: 2)
            Ellipse().fill(cyan).frame(width: 2.6, height: 6.5)
        }
        .frame(width: 14, height: 10)
    }

    private var accessibilityLabel: String {
        switch provenance {
        case .userConfirmed:
            return "Merged identity, confirmed by you"
        case .verifiedBioCrossLink:
            return "Merged identity, verified via cross-network bio links"
        case .handleConvention:
            return "Merged identity, suggested from matching handles"
        }
    }
}

#if DEBUG
struct MergedIdentityChip_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            MergedIdentityChip(provenance: .userConfirmed)
            MergedIdentityChip(provenance: .verifiedBioCrossLink)
            MergedIdentityChip(provenance: .handleConvention)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }
}
#endif
