import Foundation

// MARK: - TimelineSearchHit

/// A single matched post surfaced by timeline search.
public struct TimelineSearchHit: Identifiable, Hashable {
    public enum Source: Hashable {
        /// Matched in the loaded `UnifiedTimelineController` buffer.
        case clientBuffer
        /// Returned by a network search API.
        case remote(platform: SocialPlatform)
    }

    public let post: Post
    public let source: Source

    public var id: String {
        switch source {
        case .clientBuffer:
            return "client:\(post.id)"
        case .remote(let platform):
            return "remote:\(platform.rawValue):\(post.id)"
        }
    }

    public static func == (lhs: TimelineSearchHit, rhs: TimelineSearchHit) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - TimelineSearchContext

/// The scope in which a timeline search runs. Set at presentation time.
/// When the user invokes search from the unified home timeline, `scope` is
/// `.unified`. When invoked from inside a pinned timeline, `scope` carries
/// that pin's platforms (and, in v1.x, its account/feed filter).
public struct TimelineSearchContext: Equatable {
    public enum Scope: Equatable {
        /// Unified home timeline — both networks.
        case unified
        /// A pinned timeline scoped to specific platforms.
        case pinned(platforms: Set<SocialPlatform>, label: String)
    }

    public let scope: Scope

    public init(scope: Scope) {
        self.scope = scope
    }

    public var platforms: Set<SocialPlatform> {
        switch scope {
        case .unified:
            return Set(SocialPlatform.allCases)
        case .pinned(let platforms, _):
            return platforms
        }
    }

    public var displayLabel: String? {
        switch scope {
        case .unified: return nil
        case .pinned(_, let label): return label
        }
    }

    public static let unified = TimelineSearchContext(scope: .unified)
}

// MARK: - TimelineSearchPhase

/// Lifecycle of the layered search.
public enum TimelineSearchPhase: Equatable {
    case idle                     // empty query
    case debouncing               // query typed, debounce window not yet elapsed
    case filtering                // client-side scan running
    case clientResultsOnly        // client-side done, server-side in flight
    case complete                 // both sides done
    case clientResultsOnlyFailed  // server failed; client results still shown
}

// MARK: - TimelineSearchSection

/// A renderable section in the results list.
public enum TimelineSearchSection: Identifiable, Equatable {
    /// "Already in your timeline" — client buffer hits.
    case client(hits: [TimelineSearchHit])
    /// "From <Network>" — server hits for a single platform.
    case remote(platform: SocialPlatform, hits: [TimelineSearchHit])

    public var id: String {
        switch self {
        case .client: return "client"
        case .remote(let platform, _): return "remote-\(platform.rawValue)"
        }
    }

    public var hits: [TimelineSearchHit] {
        switch self {
        case .client(let hits): return hits
        case .remote(_, let hits): return hits
        }
    }
}
