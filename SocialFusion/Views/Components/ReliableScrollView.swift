import SwiftUI
import UIKit

/// UIKit-based scroll view for reliable position restoration
/// Wraps UIScrollView in UIViewRepresentable to avoid SwiftUI ScrollView timing issues
struct ReliableScrollView<Content: View>: UIViewRepresentable {

    // MARK: - Properties

    @Binding var scrollPosition: ScrollPosition
    let content: Content
    let onScrollPositionChanged: (Int, CGFloat) -> Void
    let onPostRead: (String) -> Void

    // MARK: - Initialization

    init(
        scrollPosition: Binding<ScrollPosition>,
        onScrollPositionChanged: @escaping (Int, CGFloat) -> Void = { _, _ in },
        onPostRead: @escaping (String) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self._scrollPosition = scrollPosition
        self.onScrollPositionChanged = onScrollPositionChanged
        self.onPostRead = onPostRead
        self.content = content()
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag

        // Ensure proper safe area handling
        scrollView.contentInsetAdjustmentBehavior = .automatic

        // Create hosting controller for SwiftUI content
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear

        scrollView.addSubview(hostingController.view)

        // Store hosting controller in coordinator
        context.coordinator.hostingController = hostingController

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Update content
        context.coordinator.hostingController?.rootView = content

        // Layout hosting controller
        if let hostingView = context.coordinator.hostingController?.view {
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            // Remove existing constraints
            hostingView.removeFromSuperview()
            scrollView.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
                hostingView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            ])

            // Force layout
            hostingView.setNeedsLayout()
            hostingView.layoutIfNeeded()

            // Update scroll content size
            let contentSize = hostingView.intrinsicContentSize
            if contentSize.height > 0 {
                scrollView.contentSize = CGSize(
                    width: scrollView.bounds.width, height: contentSize.height)
            }
        }

        // Restore position if needed
        restorePositionIfNeeded(scrollView, position: scrollPosition)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            scrollPosition: $scrollPosition,
            onScrollPositionChanged: onScrollPositionChanged,
            onPostRead: onPostRead
        )
    }

    // MARK: - Private Methods

    private func restorePositionIfNeeded(_ scrollView: UIScrollView, position: ScrollPosition) {
        switch position {
        case .top:
            // Account for any content insets (navigation bar, etc.)
            let topInset = scrollView.adjustedContentInset.top
            let targetY = -topInset

            if abs(scrollView.contentOffset.y - targetY) > 1 {
                scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
                print("🎯 ReliableScrollView: Restored to top (y: \(targetY))")
            }

        case .index(let index, let offset):
            // Safety check: Don't restore to invalid positions
            guard index >= 0 && scrollView.contentSize.height > 0 else {
                print(
                    "🎯 ReliableScrollView: Invalid index \(index) or content size, falling back to top"
                )
                scrollView.setContentOffset(
                    CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
                return
            }

            // Calculate position based on estimated item height
            let estimatedItemHeight: CGFloat = 200  // Estimate for post cards
            let topInset = scrollView.adjustedContentInset.top
            let targetY = CGFloat(index) * estimatedItemHeight + offset - topInset

            // Ensure we don't scroll beyond content
            let maxY = max(
                -topInset,
                scrollView.contentSize.height - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom)
            let clampedY = min(max(targetY, -topInset), maxY)

            if abs(scrollView.contentOffset.y - clampedY) > 10 {  // Only scroll if significantly different
                scrollView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
                print("🎯 ReliableScrollView: Restored to index \(index) (y: \(clampedY))")
            }
        }
    }
}

// MARK: - Coordinator

extension ReliableScrollView {
    class Coordinator: NSObject, UIScrollViewDelegate {

        @Binding var scrollPosition: ScrollPosition
        let onScrollPositionChanged: (Int, CGFloat) -> Void
        let onPostRead: (String) -> Void

        var hostingController: UIHostingController<Content>?
        private var isUserScrolling = false
        private var lastReportedIndex = -1

        init(
            scrollPosition: Binding<ScrollPosition>,
            onScrollPositionChanged: @escaping (Int, CGFloat) -> Void,
            onPostRead: @escaping (String) -> Void
        ) {
            self._scrollPosition = scrollPosition
            self.onScrollPositionChanged = onScrollPositionChanged
            self.onPostRead = onPostRead
        }

        // MARK: - UIScrollViewDelegate

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserScrolling = false
                updateScrollPosition(scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserScrolling = false
            updateScrollPosition(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Only update during user scrolling to avoid infinite loops
            guard isUserScrolling else { return }

            // Calculate current index based on scroll position (accounting for navigation bar)
            let estimatedItemHeight: CGFloat = 200
            let adjustedY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let currentIndex = max(0, Int(adjustedY / estimatedItemHeight))

            // Only report significant changes
            if abs(currentIndex - lastReportedIndex) >= 2 {
                lastReportedIndex = currentIndex

                // Update position
                let offset = adjustedY - (CGFloat(currentIndex) * estimatedItemHeight)
                onScrollPositionChanged(currentIndex, offset)

                // TODO: Trigger post read events based on visible content
                // This would require mapping scroll position to actual post IDs
            }
        }

        private func updateScrollPosition(_ scrollView: UIScrollView) {
            let estimatedItemHeight: CGFloat = 200
            let adjustedY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let currentIndex = max(0, Int(adjustedY / estimatedItemHeight))
            let offset = adjustedY - (CGFloat(currentIndex) * estimatedItemHeight)

            onScrollPositionChanged(currentIndex, offset)
        }
    }
}

// MARK: - Convenience Extensions

extension ReliableScrollView {
    /// Scroll to top programmatically
    func scrollToTop() {
        scrollPosition = .top
    }

    /// Scroll to specific index
    func scrollToIndex(_ index: Int, offset: CGFloat = 0) {
        scrollPosition = .index(index, offset: offset)
    }
}

// MARK: - Preview Support

#if DEBUG
    struct ReliableScrollView_Previews: PreviewProvider {
        @State static var position: ScrollPosition = .top

        static var previews: some View {
            ReliableScrollView(
                scrollPosition: $position,
                onScrollPositionChanged: { index, offset in
                    print("Position changed: \(index), \(offset)")
                },
                onPostRead: { postId in
                    print("Post read: \(postId)")
                }
            ) {
                LazyVStack {
                    ForEach(0..<50) { index in
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(height: 200)
                            .overlay(
                                Text("Item \(index)")
                                    .font(.title)
                            )
                    }
                }
            }
        }
    }
#endif
