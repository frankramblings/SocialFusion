import SwiftUI
import os.log

/// Debug utility to detect illegal layout shifts in timeline views.
/// Tracks height changes after first render and logs violations.
/// Only active in DEBUG builds.
@MainActor
final class LayoutShiftDetector {
    static let shared = LayoutShiftDetector()

    private var trackedHeights: [String: TrackedHeight] = [:]
    private let logger = Logger(subsystem: "SocialFusion", category: "LayoutShift")

    struct TrackedHeight {
        let initialHeight: CGFloat
        var lastHeight: CGFloat
        let initialWidth: CGFloat
        var lastWidth: CGFloat
        let timestamp: Date
        var renderCount: Int
    }

    private init() {}

    /// Register initial height for a component. Call on first render.
    func registerInitialHeight(
        id: String,
        height: CGFloat,
        width: CGFloat,
        componentType: String
    ) {
        #if DEBUG
        guard trackedHeights[id] == nil else { return }
        trackedHeights[id] = TrackedHeight(
            initialHeight: height,
            lastHeight: height,
            initialWidth: width,
            lastWidth: width,
            timestamp: Date(),
            renderCount: 1
        )
        #endif
    }

    /// Check if height change is legal. Call on subsequent renders.
    /// Returns true if shift is illegal (should be logged).
    func checkForIllegalShift(
        id: String,
        currentHeight: CGFloat,
        currentWidth: CGFloat,
        componentType: String,
        isUserInteraction: Bool = false,
        isDynamicTypeChange: Bool = false
    ) {
        #if DEBUG
        guard var tracked = trackedHeights[id] else {
            // First render, register it
            registerInitialHeight(id: id, height: currentHeight, width: currentWidth, componentType: componentType)
            return
        }

        tracked.renderCount += 1

        // ALLOWED EXEMPTIONS:
        // 1. Width changed (rotation, split view, container width change)
        let widthChanged = abs(currentWidth - tracked.lastWidth) > 1.0

        // 2. User interaction (CW expand, "show more", etc.)
        // 3. Dynamic Type change

        if widthChanged || isUserInteraction || isDynamicTypeChange {
            // Legal change, update tracked values silently
            tracked.lastHeight = currentHeight
            tracked.lastWidth = currentWidth
            trackedHeights[id] = tracked
            return
        }

        // Check for illegal height change
        let heightDelta = abs(currentHeight - tracked.lastHeight)
        let isSignificantChange = heightDelta > 2.0  // Allow 2pt tolerance for anti-aliasing/rounding

        if isSignificantChange {
            // ILLEGAL LAYOUT SHIFT DETECTED
            let timeSinceFirst = Date().timeIntervalSince(tracked.timestamp)
            logger.warning("""
                [LAYOUT SHIFT] Illegal height change detected!
                Component: \(componentType)
                ID: \(id)
                Height: \(tracked.lastHeight, format: .fixed(precision: 1))pt -> \(currentHeight, format: .fixed(precision: 1))pt (delta: \(heightDelta, format: .fixed(precision: 1))pt)
                Width: \(currentWidth, format: .fixed(precision: 1))pt (unchanged)
                Render count: \(tracked.renderCount)
                Time since first render: \(timeSinceFirst, format: .fixed(precision: 2))s
                """)

            // Also print to console for immediate visibility
            print("""
                ⚠️ [LAYOUT SHIFT] \(componentType) height changed illegally!
                   ID: \(id.prefix(50))
                   \(tracked.lastHeight)pt -> \(currentHeight)pt (delta: \(heightDelta)pt)
                """)
        }

        // Update tracked values
        tracked.lastHeight = currentHeight
        tracked.lastWidth = currentWidth
        trackedHeights[id] = tracked
        #endif
    }

    /// Clear tracking for a component (e.g., when it's removed from view)
    func clearTracking(id: String) {
        #if DEBUG
        trackedHeights.removeValue(forKey: id)
        #endif
    }

    /// Clear all tracking (e.g., on timeline refresh)
    func clearAllTracking() {
        #if DEBUG
        trackedHeights.removeAll()
        #endif
    }
}

// MARK: - ViewModifier for Easy Integration

/// A view modifier that tracks height changes and detects illegal layout shifts.
/// Use on media containers and link previews.
struct LayoutShiftTrackingModifier: ViewModifier {
    let id: String
    let componentType: String
    @State private var isUserInteraction = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            LayoutShiftDetector.shared.registerInitialHeight(
                                id: id,
                                height: geometry.size.height,
                                width: geometry.size.width,
                                componentType: componentType
                            )
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            LayoutShiftDetector.shared.checkForIllegalShift(
                                id: id,
                                currentHeight: newSize.height,
                                currentWidth: newSize.width,
                                componentType: componentType,
                                isUserInteraction: isUserInteraction
                            )
                        }
                }
            )
            .onDisappear {
                LayoutShiftDetector.shared.clearTracking(id: id)
            }
    }
}

extension View {
    /// Tracks layout shifts for this view. Only active in DEBUG builds.
    /// - Parameters:
    ///   - id: Unique identifier for this view instance
    ///   - componentType: Type of component (e.g., "MediaContainer", "LinkPreview")
    func trackLayoutShifts(id: String, componentType: String) -> some View {
        #if DEBUG
        return self.modifier(LayoutShiftTrackingModifier(id: id, componentType: componentType))
        #else
        return self
        #endif
    }
}
