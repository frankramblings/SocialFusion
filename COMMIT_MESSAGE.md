Fix unified search to show results from both Mastodon and Bluesky

Previously, search results were limited to one network per scope:
- Posts and Tags: only Mastodon (Bluesky decoding failures)
- Users: only Bluesky (Mastodon 500 errors)

Root Causes:
1. Bluesky search failed when posts had malformed embeds (recordWithMedia,
   nested structures, or missing fields). Decoder expected strict formats.
2. Mastodon user search returned 500 errors on some instances that don't
   support the accounts search type parameter.

Solutions:

Bluesky Search Decoding Resilience:
- Made BlueskyEmbed.record decode gracefully with try? and custom init(from:)
- Added flexible BlueskyEmbedRecord decoding to handle:
  * Direct BlueskyStrongRef
  * Nested record.record structures
  * Dictionary formats with uri/cid
- Made BlueskySearchPostsResponse decode posts individually, skipping failures
- Enhanced BlueskyExternal to handle thumb as string or BlueskyImageRef
- Made BlueskyImage.image optional, supporting fullsize/thumb direct strings
- Added error recovery in BlueskyService.searchPosts to decode from raw JSON
  when array decoding fails, ensuring partial results are returned

Mastodon User Search Fallbacks:
- Enhanced MastodonService.search to parse responses even on 500 errors
- Added multi-layer fallback in MastodonSearchProvider.searchUsers:
  1. Try search with type=accounts (standard)
  2. If 500, try without type parameter
  3. If 0 accounts, extract users from post search results
  4. Search posts matching query, extract unique account info from authors
- Made search methods return empty results instead of throwing when one
  provider fails, so the other provider's results still display

Files Modified:
- SocialFusion/Models/BlueskyModels.swift
  * Made BlueskyEmbed decode gracefully with custom init(from:)
  * Made BlueskyEmbedRecord handle multiple record formats
  * Made BlueskySearchPostsResponse decode posts individually
  * Made BlueskyExternal.thumb handle string or BlueskyImageRef
  * Made BlueskyImage.image optional, support fullsize/thumb strings
- SocialFusion/Services/BlueskyService.swift
  * Enhanced searchPosts error handling and logging
  * Improved external embed thumb extraction
- SocialFusion/Services/Search/MastodonSearchProvider.swift
  * Added multi-layer fallback for user search
  * Return empty results instead of throwing on errors
- SocialFusion/Services/Search/BlueskySearchProvider.swift
  * Return empty results instead of throwing on tag search errors
- SocialFusion/Services/Search/UnifiedSearchProvider.swift
  * Improved error handling to prevent one provider failure from blocking all results

Result:
- Posts scope: Shows results from both Mastodon and Bluesky
- Users scope: Shows results from both networks (Bluesky directly, Mastodon via fallback)
- Tags scope: Shows results from both networks
- Individual post decoding failures don't break entire searches
- Mastodon instances without user search support still return users via post extraction

The implementation maintains backward compatibility and follows existing
architecture patterns (protocol-driven design, ObservableObject stores,
service injection).
