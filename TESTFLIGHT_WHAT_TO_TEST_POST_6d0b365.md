🎯 WHAT TO TEST - Post-Commit 6d0b365 Build
Changes After: Commit 6d0b365

═══════════════════════════════════════════════════════════════

⭐ NEW: Unified Search - Cross-Platform Results
───────────────────────────────────────────────────────────────
Access: Tap Search tab/icon → Search for posts, users, or tags

**Posts Search:**
• Search for keywords/hashtags - should show results from BOTH Mastodon AND Bluesky
• Test with common terms (e.g., "apple", "tech", "#photography")
• Verify posts from both networks appear in results
• Test with posts that have:
  - Images (single and multiple)
  - Videos/GIFs
  - Link previews
  - Quote posts/boosts
  - Custom emoji in text
• Scroll through mixed results - verify smooth loading
• Tap posts from both networks - verify they open correctly

**Users Search:**
• Search for usernames or display names
• Should show users from BOTH Mastodon AND Bluesky
• Test with:
  - Exact username matches
  - Partial matches
  - Display name searches
• Tap user results - verify profiles open correctly
• Test following/unfollowing from search results

**Tags/Hashtags Search:**
• Search for hashtags (e.g., "#photography", "#tech")
• Should show results from both networks
• Verify tag results display correctly
• Tap tags - verify timeline filters correctly

**Edge Cases:**
• Search with no results - verify graceful empty state
• Search with special characters
• Search with very long queries
• Test on slow network - verify loading states
• Test with Mastodon instances that don't support user search (should still show users via fallback)

Look for: Results from both networks appear, no crashes on malformed posts, graceful error handling, smooth scrolling through mixed results

═══════════════════════════════════════════════════════════════

⭐ NEW: Muscle Memory Composer Features
───────────────────────────────────────────────────────────────
Access: Tap Compose button → Start typing

**Entity Parsing & Smart Paste:**
• Type @username - verify autocomplete appears
• Type #hashtag - verify autocomplete appears
• Type or paste a URL - verify it's automatically detected and formatted
• Paste text with mentions/hashtags/URLs - verify entities are created automatically
• Test with mixed content (text + mentions + hashtags + URLs)

**Platform Conflict Detection:**
• Compose a post with features not supported by selected platform:
  - Mastodon: Polls, quote posts (should show warning banner)
  - Bluesky: Content warnings, custom emoji (should show warning banner)
• Verify conflict banner appears and explains the issue
• Switch accounts/platforms - verify banner updates accordingly
• Test posting despite conflicts - verify behavior matches platform

**Keyboard Shortcuts (Mac Catalyst/iPad with keyboard):**
• Cmd+Enter - Post the current draft
• Cmd+K - Insert link (if supported)
• Cmd+L - Insert link (if supported)
• Cmd+. - Insert emoji picker (if supported)
• Test shortcuts work in compose view
• Verify shortcuts don't conflict with system shortcuts

**Emoji Support:**
• Type :emoji: - verify custom Mastodon emoji autocomplete appears
• Select custom emoji - verify it inserts correctly
• Test with system emoji - verify they work normally
• Test emoji in combination with text, mentions, hashtags

**Autocomplete Cache Persistence:**
• Type @username multiple times - verify it appears in autocomplete history
• Close and reopen app - verify autocomplete history persists
• Test with multiple accounts - verify history is account-specific
• Clear app data - verify cache resets correctly

**Undo/Redo Integration:**
• Type text, then undo (Cmd+Z or shake gesture)
• Verify entity ranges update correctly after undo
• Test redo (Cmd+Shift+Z)
• Test undo/redo with entities (mentions, hashtags, URLs)

**Entity Range Maintenance:**
• Type text with mentions/hashtags
• Edit text in the middle - verify entities stay correctly linked
• Delete characters - verify entity ranges adjust
• Insert text - verify entities shift correctly

Look for: Smooth autocomplete, correct entity detection, no crashes on paste, conflict warnings appear correctly, keyboard shortcuts work, emoji insert correctly, cache persists

═══════════════════════════════════════════════════════════════

⭐ IMPROVED: Custom Mastodon Emoji Rendering
───────────────────────────────────────────────────────────────
Access: View any post/profile with custom Mastodon emoji

**Profile Headers:**
• View profiles with custom emoji in display names (e.g., :paw:, :blobcatcoffee:)
• Verify emoji render as images (not text like :paw::paw:)
• Test in:
  - Profile view (main header)
  - Post author names in timeline
  - Post detail view headers
  - Reply thread author names

**Search Results:**
• Search for users with custom emoji in display names
• Verify emoji render correctly in search result rows
• Tap results - verify emoji still render in profile view

**Composer UI:**
• Open compose view
• Tap account selector - verify emoji render in account menu items
• Verify emoji render in account button label
• Check platform status bar - verify emoji render if present

**Quote Posts:**
• View quote posts from accounts with custom emoji
• Verify author name emoji render correctly
• Test boosted posts with emoji in author names

**Account Management:**
• View Accounts view - verify emoji render in account rows
• Switch accounts - verify emoji render in account picker
• View account switcher sheet - verify emoji render correctly

**Edge Cases:**
• Accounts without custom emoji - verify no errors
• Accounts with many custom emoji - verify all render
• Missing emoji data - verify graceful fallback to plain text
• Boosted posts - verify emoji render when data available

Look for: Emoji render as images (not text placeholders), consistent rendering across all UI locations, graceful fallback when emoji unavailable, no layout issues

═══════════════════════════════════════════════════════════════

⭐ NEW: Timeline-Aware Autocomplete
───────────────────────────────────────────────────────────────
Access: Compose view → Type @ or # → Autocomplete appears

**Context-Aware Suggestions:**
• Open compose from timeline view
• Type @ - verify suggestions prioritize accounts from your timeline
• Type # - verify suggestions prioritize hashtags from your timeline
• Verify suggestions are ranked by relevance (timeline context + history + network)

**Timeline Context:**
• Scroll through timeline, then compose
• Type @ - verify recently seen accounts appear higher in suggestions
• Type # - verify recently used hashtags appear higher
• Test with different timeline filters (All, Mastodon only, Bluesky only)

**Thread Context (Replies):**
• Reply to a post
• Type @ - verify the post author appears in suggestions
• Type @ - verify accounts mentioned in the thread appear
• Verify thread context influences suggestion ranking

**Multiple Suggestion Sources:**
• Type @ - verify suggestions include:
  - Accounts from timeline (context-aware)
  - Accounts from local history
  - Accounts from network search
• Verify ranking prioritizes timeline context appropriately

**Platform Logos:**
• View autocomplete overlay - verify platform logos appear (not text badges)
• Verify Mastodon logo appears for Mastodon accounts
• Verify Bluesky logo appears for Bluesky accounts
• Verify logos are clear and recognizable

**Local History:**
• Type @username multiple times
• Verify username appears in autocomplete history
• Close compose, reopen - verify history persists
• Test with multiple accounts - verify history is account-specific

**Network Suggestions:**
• Type @partial - verify network search results appear
• Type #partial - verify network search results appear
• Test with slow network - verify loading states
• Test with no network - verify graceful fallback

**Mastodon Autocomplete Fallback:**
• Test Mastodon autocomplete when API returns 500 error
• Verify fallback logic provides suggestions anyway
• Verify no crashes or error messages shown to user

**Brand Colors:**
• Verify Mastodon brand color appears correctly in autocomplete UI
• Verify Bluesky brand color appears correctly
• Check contrast and readability

Look for: Relevant suggestions based on timeline context, smooth autocomplete experience, platform logos display correctly, no crashes on API errors, suggestions update as you type

═══════════════════════════════════════════════════════════════

✅ GENERAL REGRESSION TESTING
───────────────────────────────────────────────────────────────
**Timeline:**
• Posts load correctly from both Mastodon and Bluesky
• Pull-to-refresh works
• Infinite scroll works
• Post actions (like, boost, reply) work
• Media displays correctly
• Link previews work
• Quote posts display correctly

**Account Management:**
• Account switching works
• Multiple accounts display correctly
• Account-specific timelines work
• Account picker works correctly

**Media Handling:**
• Images display correctly
• Videos play correctly
• GIFs animate correctly
• Fullscreen media view works
• Media aspect ratios are correct

**Posting:**
• Compose new posts
• Reply to posts
• Boost posts
• Edit posts (if supported)
• Delete posts
• Cross-post to multiple accounts

**Cross-Platform:**
• Test both Mastodon and Bluesky functionality
• Verify unified timeline works correctly
• Test account switching between platforms

═══════════════════════════════════════════════════════════════

⚠️ CRITICAL ISSUES TO REPORT IMMEDIATELY
───────────────────────────────────────────────────────────────
• App crashes
• Data loss
• Posts not loading
• Unable to post/share
• Search completely broken
• Autocomplete crashes or freezes
• Navigation completely broken
• Severe performance issues
• Memory leaks or excessive memory usage

═══════════════════════════════════════════════════════════════

📝 When reporting issues, include:
• Device model and iOS version
• Steps to reproduce (detailed)
• Expected vs actual behavior
• Screenshots/videos if applicable
• Frequency (every time or intermittent)
• Network type (WiFi, cellular, slow connection)
• Which platform(s) affected (Mastodon, Bluesky, or both)

═══════════════════════════════════════════════════════════════

🎯 Priority Testing Order:
1. Unified Search (cross-platform results)
2. Muscle Memory Composer (entity parsing, conflicts, shortcuts)
3. Custom Mastodon Emoji Rendering (visual verification)
4. Timeline-Aware Autocomplete (context suggestions)
5. General regression testing

Thank you for testing SocialFusion! 🚀
