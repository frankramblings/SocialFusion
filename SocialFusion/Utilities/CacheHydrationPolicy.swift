import Foundation

struct CacheHydrationPolicy {
    func shouldHydrate(hasHydrated: Bool, hasPresented: Bool, isTimelineEmpty: Bool) -> Bool {
        if hasHydrated { return false }
        if hasPresented { return false }
        return isTimelineEmpty
    }
}

