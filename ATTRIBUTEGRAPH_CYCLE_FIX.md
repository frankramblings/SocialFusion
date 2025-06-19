# AttributeGraph Cycle Fixes

## Issue
After implementing the position restoration and unread counter fixes, the app experienced massive AttributeGraph cycle warnings and "Modifying state during view update" errors.

**Symptoms:**
- Hundreds of `=== AttributeGraph: cycle detected through attribute XXXXX ===` warnings
- `Modifying state during view update, this will cause undefined behavior` errors
- Potential performance issues and UI glitches

## Root Cause
We were calling state-modifying functions during SwiftUI's view update cycle:

1. **markPostAsRead()** called in `.onAppear` - runs during view updates
2. **saveScrollPosition()** called in `.onAppear` - runs during view updates  
3. **Position restoration** using `DispatchQueue.main.async` - can conflict with view updates
4. **Scroll notifications** using `DispatchQueue.main.async` - can conflict with view updates

## Solution
Replaced all `DispatchQueue.main.async` calls with `Task { @MainActor in ... }` and added small delays to ensure we're not modifying state during SwiftUI's view update cycle.

### Fixed Code Patterns

**Before (causing cycles):**
```swift
.onAppear {
    timelineState.markPostAsRead(entry.post.id) // ❌ Immediate state change
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        timelineState.saveScrollPosition(entry.post.id) // ❌ Can conflict
    }
}
```

**After (cycle-safe):**
```swift
.onAppear {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        timelineState.markPostAsRead(entry.post.id) // ✅ Safe async
    }
    
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        timelineState.saveScrollPosition(entry.post.id) // ✅ Safe async
    }
}
```

### All Fixed Locations

1. **Post read tracking** (markPostAsRead) - Added 0.01s delay
2. **Position saving** (saveScrollPosition) - Added 0.5s delay  
3. **Position restoration** after timeline load - Added 1.0s delay
4. **Scroll notifications** (scrollToPosition) - Added 0.01s delay
5. **Restoration suggestions** - Added 0.01s delay

## Benefits
- ✅ **Eliminates AttributeGraph cycles** - No more cycle warnings
- ✅ **Prevents undefined behavior** - No more "Modifying state during view update"
- ✅ **Maintains functionality** - All features still work as expected
- ✅ **Better performance** - Reduces SwiftUI rendering conflicts
- ✅ **iOS compatibility** - Safe async patterns work on iOS 16+

## Technical Details
- `Task { @MainActor in }` ensures main thread execution like DispatchQueue.main
- Small delays (nanoseconds) ensure we're outside the view update cycle
- `@MainActor` annotation guarantees UI updates happen on main thread
- Error handling with `try? await Task.sleep()` for robustness

The app now launches smoothly without AttributeGraph warnings while maintaining all position restoration and unread counter functionality. 