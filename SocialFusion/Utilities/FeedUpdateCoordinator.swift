import Foundation
import SwiftUI

/// Coordinates layout-affecting updates with anchor preservation
/// Prevents scroll jumps when media loads or banners appear/disappear
@MainActor
class FeedUpdateCoordinator: ObservableObject {
  /// Represents a layout-affecting update
  struct LayoutUpdate {
    let postId: String
    let snapshot: PostLayoutSnapshot
    let timestamp: Date
  }
  
  private var pendingUpdates: [LayoutUpdate] = []
  private var isApplyingUpdates = false
  private var updateTask: Task<Void, Never>?
  
  /// Callback when updates should be applied
  var onApplyUpdates: (([LayoutUpdate]) -> Void)?
  
  /// Callback to capture current scroll anchor
  var onCaptureAnchor: (() -> (postId: String, offset: CGFloat)?)?
  
  /// Callback to restore scroll anchor
  var onRestoreAnchor: ((String, CGFloat) -> Void)?
  
  /// Queue a layout-affecting update
  func queueUpdate(postId: String, snapshot: PostLayoutSnapshot) {
    let update = LayoutUpdate(
      postId: postId,
      snapshot: snapshot,
      timestamp: Date()
    )
    
    // Remove any existing update for this post
    pendingUpdates.removeAll { $0.postId == postId }
    
    // Add new update
    pendingUpdates.append(update)
    
    // Schedule application
    scheduleUpdateApplication()
  }
  
  /// Apply updates immediately (for testing or urgent cases)
  func applyUpdatesImmediately() {
    guard !pendingUpdates.isEmpty else { return }
    
    let updates = pendingUpdates
    pendingUpdates.removeAll()
    
    onApplyUpdates?(updates)
  }
  
  /// Clear pending updates
  func clearPending() {
    updateTask?.cancel()
    pendingUpdates.removeAll()
  }
  
  // MARK: - Private Helpers
  
  private func scheduleUpdateApplication() {
    // Cancel existing task
    updateTask?.cancel()
    
    // Schedule new task (debounce rapid updates)
    updateTask = Task {
      // Wait a bit to batch multiple updates
      try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      
      guard !Task.isCancelled else { return }
      
      await applyUpdatesWithAnchorPreservation()
    }
  }
  
  private func applyUpdatesWithAnchorPreservation() async {
    guard !pendingUpdates.isEmpty else { return }
    guard !isApplyingUpdates else { return }
    
    isApplyingUpdates = true
    defer { isApplyingUpdates = false }
    
    // Capture current anchor
    guard let anchor = onCaptureAnchor?() else {
      // No anchor available - apply updates without preservation
      let updates = pendingUpdates
      pendingUpdates.removeAll()
      onApplyUpdates?(updates)
      return
    }
    
    // Apply updates
    let updates = pendingUpdates
    pendingUpdates.removeAll()
    onApplyUpdates?(updates)
    
    // Wait for layout to settle
    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
    
    // Restore anchor
    onRestoreAnchor?(anchor.postId, anchor.offset)
  }
}

/// Helper to track scroll position for anchor preservation
struct ScrollAnchorTracker {
  var topVisiblePostId: String?
  var topVisibleOffset: CGFloat = 0
  var visiblePostIds: Set<String> = []
  
  mutating func update(
    topPostId: String?,
    topOffset: CGFloat,
    visibleIds: Set<String>
  ) {
    topVisiblePostId = topPostId
    topVisibleOffset = topOffset
    visiblePostIds = visibleIds
  }
  
  func captureAnchor() -> (postId: String, offset: CGFloat)? {
    guard let postId = topVisiblePostId else { return nil }
    return (postId, topVisibleOffset)
  }
}
