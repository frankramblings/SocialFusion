import SwiftUI

/// Unified Timeline View - Single Implementation
/// This is now a simple wrapper around ConsolidatedTimelineView to maintain API compatibility
/// while ensuring only one timeline implementation is used throughout the app
struct UnifiedTimelineView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager

    init() {
        print("🔗 UnifiedTimelineView: Initialized as wrapper around ConsolidatedTimelineView")
    }

    var body: some View {
        ConsolidatedTimelineView(serviceManager: serviceManager)
    }
}

// MARK: - Preview
struct UnifiedTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedTimelineView()
            .environmentObject(SocialServiceManager())
    }
}
