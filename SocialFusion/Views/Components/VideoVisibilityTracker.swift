import SwiftUI

/// PreferenceKey to track video visibility in scroll views
struct VideoVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Bool] = [:]
    
    static func reduce(value: inout [String: Bool], nextValue: () -> [String: Bool]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// View modifier that tracks visibility of a video view
struct VideoVisibilityModifier: ViewModifier {
    let videoID: String
    @Binding var isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: VideoVisibilityPreferenceKey.self,
                            value: [videoID: isViewVisible(geometry: geometry)]
                        )
                }
            )
            .onPreferenceChange(VideoVisibilityPreferenceKey.self) { visibilityMap in
                if let visible = visibilityMap[videoID] {
                    isVisible = visible
                }
            }
    }
    
    /// Determines if the view is visible based on its frame
    /// Uses a threshold: video is considered visible if > 50% is on screen
    private func isViewVisible(geometry: GeometryProxy) -> Bool {
        let frame = geometry.frame(in: .global)
        let screenBounds = UIScreen.main.bounds
        
        // Check if view intersects with screen bounds
        let intersection = screenBounds.intersection(frame)
        
        // Consider visible if at least 30% of the view is on screen
        // Reduced from 50% to match industry standards (IceCubesApp, Bluesky use 20-30%)
        // This allows videos to start playing earlier, improving perceived performance
        let visibleArea = intersection.width * intersection.height
        let totalArea = frame.width * frame.height
        
        guard totalArea > 0 else { return false }
        
        let visibilityRatio = visibleArea / totalArea
        return visibilityRatio >= 0.3
    }
}

extension View {
    /// Tracks visibility of a video view for smart playback control
    func trackVideoVisibility(id: String, isVisible: Binding<Bool>) -> some View {
        self.modifier(VideoVisibilityModifier(videoID: id, isVisible: isVisible))
    }
}
