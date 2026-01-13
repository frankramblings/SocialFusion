import Foundation

/// Protocol for providing timeline context to autocomplete
/// This keeps autocomplete decoupled from UI controllers and enables testability
public protocol TimelineContextProvider: Sendable {
  /// Get context snapshot for a given scope
  func snapshot(for scope: AutocompleteTimelineScope) -> TimelineContextSnapshot
  
  /// Update snapshot when timeline changes (called by timeline pipeline)
  func updateSnapshot(posts: [Post], scope: AutocompleteTimelineScope)
}
