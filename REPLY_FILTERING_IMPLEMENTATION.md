# Unified Thread Reply Filter Implementation

## Overview

This implementation adds cross-platform reply visibility filtering that mimics Bluesky's behavior: show a reply in the user's "Following" feed only if **at least two participants in the thread are followed accounts**. The filtering applies to both Mastodon and Bluesky posts.

## Architecture

### Core Components

#### 1. UserID (`SocialFusion/Models/SocialModels.swift`)
- Normalized user identifier that works across platforms
- Format: `@handle@instance` (Mastodon) or `handle.bsky.social` (Bluesky)
- Provides consistent identification across platform boundaries

#### 2. ThreadParticipantResolver Protocol
- Abstract interface for resolving thread participants
- Platform-agnostic design allows for easy extension to new networks

#### 3. Platform-Specific Resolvers

**MastodonThreadResolver** (`SocialFusion/Services/MastodonThreadResolver.swift`)
- Uses existing `/statuses/:id/context` API
- Extracts participants from ancestors and descendants
- Handles Mastodon-specific user identification

**BlueskyThreadResolver** (`SocialFusion/Services/BlueskyThreadResolver.swift`)
- Uses existing `getPostThread` API
- Processes nested thread structure
- Handles Bluesky DID and handle normalization

#### 4. PostFeedFilter (`SocialFusion/Models/SocialModels.swift`)
- Main filtering logic coordinator
- Caches thread participant results (5-minute TTL)
- Includes feature flag for debugging (`isReplyFilteringEnabled`)

### Integration Points

#### SocialServiceManager
- Lazy-initialized `PostFeedFilter` instance
- Applied during `safelyUpdateTimeline()` processing
- Public API for enabling/disabling filtering
- Placeholder followed accounts logic (treats logged-in accounts as followed)

## Filtering Logic

### Always Show
1. **Top-level posts** from any user (not replies)
2. **Self-replies** from followed users (thread continuation)

### Reply Filtering Rules
For posts with `inReplyToID != nil`:

1. **Author is followed** → Always show (self-replies)
2. **Thread has ≥2 followed participants** → Show
3. **Thread has <2 followed participants** → Hide
4. **Error resolving thread** → Show (fail-safe)

### Example Scenarios

```
Thread: Alice → Bob → Charlie

Followed: [Alice, Bob]
- Alice's post: ✅ (top-level)
- Bob's reply: ✅ (followed author)  
- Charlie's reply: ✅ (thread has Alice + Bob = 2 followed)

Followed: [Alice]
- Alice's post: ✅ (top-level)
- Bob's reply: ❌ (only 1 followed participant)
- Charlie's reply: ❌ (only 1 followed participant)
```

## Performance Considerations

### Caching Strategy
- Thread participants cached for 5 minutes per post
- Concurrent-safe caching with barrier queues
- Automatic cleanup of stale entries

### Error Handling
- Network failures default to showing the reply
- Prevents aggressive filtering due to temporary issues
- Detailed logging for debugging

### Async Processing
- Timeline filtering happens asynchronously
- UI remains responsive during thread resolution
- Batch processing of posts

## Testing

### Unit Tests (`Tests/SocialFusionTests/PostFeedFilterTests.swift`)
- ✅ Top-level posts always included
- ✅ Self-replies from followed users included
- ✅ Replies with 2+ followed participants included
- ✅ Replies with <2 followed participants excluded
- ✅ Cross-platform compatibility (Mastodon + Bluesky)
- ✅ Feature flag functionality
- ✅ Error handling (defaults to include)

### Test Scenarios Covered
```swift
// Always include top-level posts
testTopLevelPostFromFollowedUserIsAlwaysIncluded()
testTopLevelPostFromUnfollowedUserIsAlwaysIncluded()

// Reply filtering logic
testReplyFromFollowedUserIsAlwaysIncluded()
testReplyWithTwoFollowedParticipantsIsIncluded()
testReplyWithOneFollowedParticipantIsExcluded()

// Cross-platform support
testBlueskyReplyFiltering()

// Feature controls
testFilteringDisabledIncludesAllReplies()

// Error handling
testThreadResolutionErrorDefaultsToInclude()
```

## Debug Interface

### DebugOptionsView Integration
- Toggle to enable/disable reply filtering
- Timeline statistics (total posts, replies, top-level)
- Cache management controls
- Real-time filtering status

### Debug Controls
```swift
// Enable/disable filtering
serviceManager.setReplyFilteringEnabled(false)

// Check current state
let isEnabled = serviceManager.isReplyFilteringEnabled
```

## API Usage

### Mastodon Context API
```
GET /api/v1/statuses/:id/context
```
Returns ancestors and descendants for thread reconstruction.

### Bluesky Thread API
```
GET /xrpc/app.bsky.feed.getPostThread?uri={postUri}&depth=10
```
Returns nested thread structure with parent/reply relationships.

## Current Limitations

### Following List Simulation
- Currently treats all logged-in accounts as "followed"
- Real implementation would require:
  - Mastodon: `GET /api/v1/accounts/:id/following`
  - Bluesky: `app.bsky.graph.getFollows`

### Performance Optimization Opportunities
1. **Batch thread resolution** for multiple posts
2. **Persistent caching** across app sessions
3. **Background prefetching** of thread contexts
4. **Following list caching** with sync updates

## Future Enhancements

### Real Following Lists
```swift
// Mastodon following list
func fetchMastodonFollowing(for account: SocialAccount) async throws -> Set<UserID>

// Bluesky following list  
func fetchBlueskyFollowing(for account: SocialAccount) async throws -> Set<UserID>
```

### Advanced Filtering Options
- User-configurable participant threshold (2, 3, 4+)
- Whitelist/blacklist specific users
- Different rules per platform
- Time-based filtering (only recent threads)

### Analytics
- Track filtering effectiveness
- Monitor cache hit rates
- Measure performance impact

## Configuration

### Feature Flags
```swift
// Disable filtering globally
postFeedFilter.isReplyFilteringEnabled = false

// Cache configuration
let cacheLifetime: TimeInterval = 300 // 5 minutes
```

### Debug Logging
```
🚫 Filtered out reply from user3@mastodon.social - insufficient followed participants in thread
⚠️ PostFeedFilter: Error resolving thread participants for post 123: Network timeout
🔧 SocialServiceManager: Reply filtering disabled
```

## Migration Notes

This implementation is:
- ✅ **Backward compatible** - no breaking changes
- ✅ **Feature-flagged** - can be disabled if issues arise
- ✅ **Platform-agnostic** - extends to future networks
- ✅ **Performance-conscious** - caching and async processing
- ✅ **Well-tested** - comprehensive unit test coverage

The filter integrates seamlessly with existing timeline processing and can be safely deployed with the feature flag disabled initially for gradual rollout. 