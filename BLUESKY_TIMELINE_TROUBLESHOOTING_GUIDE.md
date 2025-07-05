# Bluesky Timeline Troubleshooting Guide

## Problem: No Bluesky Posts Appearing in Feed

User reports only seeing Mastodon posts, no Bluesky posts in the unified timeline.

## Diagnostic Steps

### 1. Account Selection Issues

**Most Likely Cause**: Account selection might be filtering out Bluesky accounts.

**Quick Fixes to Try:**

1. **Reset Account Selection to "All"**:
   - Open Settings → Accounts
   - Tap "Reset Account Selection to All" button in debug section
   - Or manually ensure "All Accounts" is selected in account picker

2. **Check Selected Account IDs**:
   - Look for `selectedAccountIds` in debug output
   - Should contain `["all"]` or include Bluesky account IDs

### 2. Token/Authentication Issues

**Symptoms**: Bluesky accounts exist but API calls fail silently

**Check**:
- Token status in Debug view (Settings → Accounts → Debug Info)
- Look for "Token Status: Valid" vs "Expired" or "Missing"

**Fix**: Re-authenticate Bluesky accounts if tokens are expired

### 3. Account Loading Issues

**Symptoms**: Bluesky accounts not loading from keychain/storage

**Check**:
- Number of Bluesky accounts in debug info
- Account list in Settings → Accounts

**Debug Logging**: Look for these in console:
```
🔧 SocialServiceManager: Bluesky accounts: X
🔧 SocialServiceManager: Account X: username (bluesky) - ID: abc123
```

### 4. Timeline Fetching Issues

**Symptoms**: Accounts exist and are selected, but no posts fetched

**Check Console Logs For**:
```
🔄 SocialServiceManager: Fetching Bluesky timeline for username
🔄 SocialServiceManager: Bluesky fetch completed - X posts
```

**Common Issues**:
- Network errors (check error messages)
- API rate limiting
- Empty timeline response from Bluesky API

## Step-by-Step Troubleshooting

### Step 1: Verify Account Selection
```swift
// Check in DebugBlueskyView or console
print("Selected IDs: \(serviceManager.selectedAccountIds)")
print("Bluesky accounts: \(serviceManager.blueskyAccounts.count)")
print("Total accounts: \(serviceManager.accounts.count)")
```

**Expected**: 
- `selectedAccountIds` contains `"all"` OR specific Bluesky account IDs
- `blueskyAccounts.count > 0`

### Step 2: Force Account Selection Reset
```swift
// In DebugBlueskyView - tap this button:
serviceManager.selectedAccountIds = ["all"]
```

### Step 3: Test Bluesky Connection
```swift
// Use "Test Bluesky Connection" button in debug view
// Should return: "Bluesky connection successful! Fetched X posts"
```

### Step 4: Force Timeline Refresh
```swift
// Use "Force Refresh Timeline" button
// Check console for detailed fetch logs
```

## Common Fixes

### Fix 1: Account Selection Reset
If you suspect account selection issues:

1. Go to Settings → Accounts
2. Look for "Debug Info" section (might be hidden)
3. Tap "Reset Account Selection to All" 
4. Or manually select "All Accounts" in main timeline picker

### Fix 2: Re-authenticate Bluesky Accounts
If tokens are expired:

1. Go to Settings → Accounts  
2. Remove existing Bluesky account
3. Add it back with current credentials
4. Check that "Selected: Yes" appears for the account

### Fix 3: Clear Timeline Cache
If timeline is stuck with old data:

1. Force close app completely
2. Reopen app
3. Pull-to-refresh on timeline
4. Check if Bluesky posts appear

### Fix 4: Manual Account Selection
If "All Accounts" isn't working:

1. In timeline view, tap account picker dropdown
2. Select specific Bluesky account instead of "All"
3. Verify posts load for that account
4. Then switch back to "All Accounts"

## Developer Debug Steps

### Add Debug Button to Force Account Refresh
```swift
Button("Force Reload Accounts") {
    Task {
        await serviceManager.forceReloadAccounts()
    }
}
```

### Check getAccountsToFetch() Logic
Look for this in console when timeline refreshes:
```
🔧 SocialServiceManager: getAccountsToFetch() called
🔧 SocialServiceManager: selectedAccountIds = [all]
🔧 SocialServiceManager: Using ALL accounts (X)
🔧 SocialServiceManager: Account 0: username (platform) - ID: abc123
```

### Verify Timeline Processing
Check for these logs:
```
🔄 SocialServiceManager: Fetching timeline for X accounts
🔄 SocialServiceManager: Account 0: username (bluesky)
🔄 SocialServiceManager: Starting fetch for username
🔄 SocialServiceManager: Bluesky fetch completed - X posts
🔄 SocialServiceManager: Collected X posts from accounts
```

## API-Level Debugging

### BlueskyService.fetchTimeline Debug
Look for:
```
✅ [BlueskyService] Valid profile URL for bluesky: url (author: name)
📥 [ImageCache] Cache MISS, loading: filename (priority: high)
🔄 [SocialServiceManager] Bluesky fetch completed - X posts
```

### Common API Errors
- `401 Unauthorized`: Token expired, need re-auth
- `429 Rate Limited`: Too many requests, wait before retry
- `Empty timeline response`: API returned no posts (might be normal)

## Quick Test Script

Add this temporary button to test everything:

```swift
Button("Full Bluesky Debug Test") {
    Task {
        print("=== BLUESKY DEBUG TEST ===")
        print("Bluesky accounts: \(serviceManager.blueskyAccounts.count)")
        print("Selected IDs: \(serviceManager.selectedAccountIds)")
        print("Timeline posts: \(serviceManager.unifiedTimeline.count)")
        
        let blueskyPosts = serviceManager.unifiedTimeline.filter { $0.platform == .bluesky }
        print("Bluesky posts in timeline: \(blueskyPosts.count)")
        
        // Force reset and refresh
        serviceManager.selectedAccountIds = ["all"]
        try? await serviceManager.refreshTimeline(force: true)
        
        let newBlueskyPosts = serviceManager.unifiedTimeline.filter { $0.platform == .bluesky }
        print("After refresh - Bluesky posts: \(newBlueskyPosts.count)")
    }
}
```

## Most Likely Solutions

Based on the codebase analysis, try these in order:

1. **Account Selection Reset**: `serviceManager.selectedAccountIds = ["all"]`
2. **Force Timeline Refresh**: Use debug button or pull-to-refresh
3. **Check Token Status**: Re-authenticate if expired
4. **Verify Account Loading**: Check account count in debug view

The issue is most likely in the account selection logic - the app might be filtering out Bluesky accounts unintentionally. 