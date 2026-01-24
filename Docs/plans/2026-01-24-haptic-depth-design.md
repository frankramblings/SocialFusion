# Haptic Depth: System Event Haptics Design

**Date**: 2026-01-24
**Status**: Approved
**Scope**: Create unified HapticEngine utility, add haptics to system events, migrate existing patterns

## Problem

Haptics are present for button taps throughout the app (~20 call sites across 11 files), but missing for "system events" like:
- Pull-to-refresh completion
- Account switching
- Follow/unfollow confirmation

Current implementation is ad-hoc: each file creates its own `UIImpactFeedbackGenerator` inline, with inconsistent styles and rarely uses `.prepare()`.

## Goals

1. **Confirmation & closure** - "Your action completed successfully"
2. **Awareness without looking** - Feel the app working during multitasking
3. **Delight & polish** - Premium, native feel matching Apple's patterns

## Design

### HapticEngine Utility

**Location**: `SocialFusion/Utilities/HapticEngine.swift`

```swift
import UIKit

enum HapticEngine {
    // MARK: - User Actions
    case tap          // Light impact - standard button press
    case selection    // Selection feedback - toggles, mode changes

    // MARK: - System Events
    case success      // Notification success - post sent, refresh with new content
    case warning      // Notification warning - partial success
    case error        // Notification error - network failure

    // MARK: - Contextual
    case refreshComplete(hasNewContent: Bool)

    func trigger() {
        switch self {
        case .tap:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .refreshComplete(let hasNewContent):
            if hasNewContent {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    static func prepare(_ pattern: HapticEngine) {
        // Pre-warm generators for latency-sensitive moments
        switch pattern {
        case .tap:
            UIImpactFeedbackGenerator(style: .light).prepare()
        case .selection:
            UISelectionFeedbackGenerator().prepare()
        case .success, .warning, .error, .refreshComplete:
            UINotificationFeedbackGenerator().prepare()
        }
    }
}
```

### Haptic Vocabulary

| Event | Pattern | Apple Equivalent | Feel |
|-------|---------|------------------|------|
| Button tap | `.tap` | `UIImpactFeedbackGenerator(.light)` | Quick, subtle click |
| Toggle/selection | `.selection` | `UISelectionFeedbackGenerator` | Softer "notch" feel |
| Post sent | `.success` | `UINotificationFeedbackGenerator(.success)` | Satisfying triple-pulse |
| Refresh with new posts | `.success` | `UINotificationFeedbackGenerator(.success)` | Same as post sent |
| Refresh, no new posts | `.tap` | `UIImpactFeedbackGenerator(.light)` | Acknowledges without fanfare |
| Follow/Unfollow | `.success` | `UINotificationFeedbackGenerator(.success)` | Confirms relationship change |
| Account switched | `.selection` | `UISelectionFeedbackGenerator` | Mode-change feel |
| Partial success | `.warning` | `UINotificationFeedbackGenerator(.warning)` | Double-pulse, heavier |
| Error | `.error` | `UINotificationFeedbackGenerator(.error)` | Strong double-buzz |

## Integration Points

### A) Pull-to-Refresh Completion

**Files**: `ConsolidatedTimelineView.swift`, `AccountTimelineView.swift`, `NotificationsView.swift`, `SearchView.swift`

Add after refresh completes:
```swift
HapticEngine.refreshComplete(hasNewContent: bufferedCount > 0).trigger()
```

### B) Post Sent Successfully

**Files**: `ComposeView.swift`, `PostDetailView.swift`

Migrate existing `UINotificationFeedbackGenerator().notificationOccurred(.success)` to:
```swift
HapticEngine.success.trigger()
```

### C) Follow/Unfollow Confirmation

**File**: `RelationshipBar.swift`

Add after successful API call:
```swift
HapticEngine.success.trigger()
```

### D) Account Switch

**File**: `AccountsView.swift`

Replace existing `.light` impact with:
```swift
HapticEngine.selection.trigger()
```

## Files Changed

| File | Change |
|------|--------|
| `Utilities/HapticEngine.swift` | **New file** |
| `ConsolidatedTimelineView.swift` | Add refresh haptic (~2 locations) |
| `AccountTimelineView.swift` | Add refresh haptic (~2 locations) |
| `NotificationsView.swift` | Add refresh haptic (~2 locations) |
| `SearchView.swift` | Add refresh haptic (~1 location) |
| `ComposeView.swift` | Migrate 3 existing haptics |
| `PostDetailView.swift` | Migrate 2 existing haptics |
| `AccountsView.swift` | Change to `.selection` |
| `RelationshipBar.swift` | Add follow/unfollow haptic |

## Migration Strategy

**Phase 1 (this pass)**: Create utility, add system events, migrate files listed above.

**Phase 2 (future)**: Migrate remaining inline haptics opportunistically when touching those files for other reasons.

## Testing

- [ ] Pull-to-refresh on timeline - feel success pulse when new posts arrive
- [ ] Pull-to-refresh when current - feel light tap acknowledgment
- [ ] Send a post - feel success pulse on completion
- [ ] Follow/unfollow a user - feel success pulse
- [ ] Switch accounts - feel selection feedback
- [ ] Trigger an error - feel error buzz
