import SwiftUI

/// High-contrast variant of `PlatformLogoBadge`.
///
/// Design rationale: under deuteranopia / protanopia / tritanopia the Bluesky
/// blue (`#0085FF`) and the Mastodon purple (`#6364FF`) compress toward the
/// same neutral grey, and color tinting alone fails to distinguish them. This
/// variant carries network identity through *fill style*:
///
/// - **Bluesky** — a filled colored glyph with a 1.5pt black outline. The
///   filled rendering reads as "solid" at a glance.
/// - **Mastodon** — an outlined glyph (no color fill, dark grey 1.5pt stroke
///   following the silhouette). The outlined rendering reads as "hollow."
///
/// Filled vs. hollow is the most colorblind-safe coding pair we can stack on
/// top of the existing shape coding.
struct HighContrastBadgeBody: View {
    let platform: SocialPlatform
    let logoImageName: String
    let size: CGFloat
    let shadowEnabled: Bool

    var body: some View {
        ZStack {
            // Background plate: opaque white so high-contrast borders read
            // against any timeline background. Slight grey ring for affordance.
            Circle()
                .fill(Color.white)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.85), lineWidth: 1.0)
                )

            glyph
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(shadowEnabled ? 0.20 : 0), radius: 1.5, x: 0, y: 1)
    }

    @ViewBuilder
    private var glyph: some View {
        switch platform {
        case .bluesky:
            // Filled colored glyph with thick black outline. Outline is an
            // 8-direction offset ring of black copies behind the colored copy.
            ZStack {
                ForEach(strokeOffsets, id: \.self) { offset in
                    Image(logoImageName)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Color.black)
                        .offset(x: offset.width, y: offset.height)
                }
                Image(logoImageName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color(red: 0, green: 133 / 255, blue: 255 / 255))
            }
            .frame(width: glyphSide, height: glyphSide)

        case .mastodon:
            // Outlined-only glyph: a slightly inset hollow stroke produced by
            // stacking a dark silhouette with a slightly smaller white copy.
            ZStack {
                Image(logoImageName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.black)
                    .frame(width: glyphSide, height: glyphSide)
                Image(logoImageName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.white)
                    .frame(width: glyphSide * 0.78, height: glyphSide * 0.78)
            }
        }
    }

    private var glyphSide: CGFloat { size * 0.62 }

    private var strokeOffsets: [CGSize] {
        let m = max(size * 0.06, 1.0)
        return [
            CGSize(width:  m, height:  0),
            CGSize(width: -m, height:  0),
            CGSize(width:  0, height:  m),
            CGSize(width:  0, height: -m),
            CGSize(width:  m, height:  m),
            CGSize(width: -m, height:  m),
            CGSize(width:  m, height: -m),
            CGSize(width: -m, height: -m),
        ]
    }
}

#Preview {
    HStack(spacing: 16) {
        HighContrastBadgeBody(platform: .bluesky,
                              logoImageName: "BlueskyLogo",
                              size: 32, shadowEnabled: true)
        HighContrastBadgeBody(platform: .mastodon,
                              logoImageName: "MastodonLogo",
                              size: 32, shadowEnabled: true)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
