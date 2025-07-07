import LinkPresentation
import SwiftUI

/// A high-performance link preview that only loads when visible and maintains stable layout
struct PerformantLinkPreview: View {
    let url: URL
    let idealHeight: CGFloat

    @State private var isVisible = false
    @State private var hasLoaded = false
    @Environment(\.colorScheme) private var colorScheme

    init(url: URL, idealHeight: CGFloat = 100) {
        self.url = url
        self.idealHeight = idealHeight
    }

    var body: some View {
        Group {
            if isVisible && !hasLoaded {
                StabilizedLinkPreview(url: url, idealHeight: idealHeight)
                    .onAppear {
                        // Use Task to defer state updates outside view rendering cycle
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                            hasLoaded = true
                        }
                    }
            } else if hasLoaded {
                StabilizedLinkPreview(url: url, idealHeight: idealHeight)
            } else {
                // Placeholder with identical dimensions
                LinkPreviewPlaceholder(url: url, height: idealHeight)
            }
        }
        .frame(maxWidth: .infinity, idealHeight: idealHeight)
        .onAppear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                // Small delay to avoid loading too many at once
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                isVisible = true
            }
        }
        .onDisappear {
            // Use Task to defer state updates outside view rendering cycle
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                isVisible = false
            }
        }
    }
}

/// Consistent placeholder that matches the final link preview dimensions
private struct LinkPreviewPlaceholder: View {
    let url: URL
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Image placeholder
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 80, height: height - 24)
                .cornerRadius(8)
                .overlay(
                    Image(systemName: "link")
                        .font(.title3)
                        .foregroundColor(.secondary)
                )

            // Text placeholders
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(4)

                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 12)
                    .frame(maxWidth: 120)
                    .cornerRadius(4)

                Spacer()
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, idealHeight: height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
        .onTapGesture {
            UIApplication.shared.open(url)
        }
    }
}
