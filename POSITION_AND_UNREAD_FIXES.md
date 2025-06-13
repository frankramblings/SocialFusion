# Position Restoration & Unread Counter Fixes

## 🚨 **Issues Identified & Fixed**

### **1. App Launches at Top (Position Restoration Not Working)**
**Problem:** Restoration was running before timeline had posts loaded.

**Fix:** 
- Moved position restoration to **after timeline loads** in `onReceive(viewModel.$state)`
- Added 1-second delay after timeline load to ensure posts are rendered
- Disabled old restoration task that was running too early

### **2. Unread Counter Shows All Posts as Unread**
**Problem:** All posts were considered "new" on first app launch.

**Fix:**
- Modified `isPostNew()` to **not mark all posts as new on first load**
- Changed unread count to **only count actually new posts** (`isNew && !isRead`)
- Fixed logic: `guard isInitialized else { return false }`

### **3. Counter Doesn't Change When Scrolling**
**Problem:** Posts weren't being marked as read OR unread count wasn't updating.

**Fix:**
- Enabled **debug logging** to see what's happening
- Fixed unread count calculation to use both `isNew` and `isRead` flags
- Added better logging: `"Unread count updated to X (new posts only)"`

### **4. Counter Doesn't Disappear Until Pull to Refresh**
**Problem:** `clearAllUnread()` wasn't clearing the "new" flag.

**Fix:**
- Modified `clearAllUnread()` to **clear both `isRead` and `isNew` flags**
- Now properly resets counter when scrolling to top

## 🔧 **Code Changes Made**

### **Position Restoration Fix**
```swift
// NEW: Restoration after timeline loads
.onReceive(viewModel.$state) { state in
    if !posts.isEmpty {
        let wasFirstLoad = !timelineState.isInitialized
        timelineState.updateFromPosts(posts, preservePosition: timelineState.isInitialized)
        
        // If this was the first load, trigger position restoration
        if wasFirstLoad {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let savedPosition = timelineState.getRestoreScrollPosition(),
                   let targetEntry = displayEntries.first(where: { $0.post.id == savedPosition }) {
                    NotificationCenter.default.post(name: .scrollToPosition, ...)
                }
            }
        }
    }
}
```

### **Unread Count Logic Fix**
```swift
// BEFORE (all posts considered new):
private func isPostNew(_ post: Post) -> Bool {
    return post.createdAt > lastVisitDate && !isPostRead(post.id)
}

// AFTER (only genuinely new posts):
private func isPostNew(_ post: Post) -> Bool {
    guard isInitialized else { return false } // Don't mark all posts as new on first load
    return post.createdAt > lastVisitDate && !isPostRead(post.id)
}
```

### **Unread Counter Calculation Fix**
```swift
// BEFORE (counted all unread posts):
let newUnreadCount = entries.filter { !$0.isRead }.count

// AFTER (only count new posts):
let newUnreadCount = entries.filter { $0.isNew && !$0.isRead }.count
```

### **Clear All Unread Fix**
```swift
// BEFORE (only cleared read flag):
entries[i].isRead = true

// AFTER (clear both flags):
entries[i].isRead = true
entries[i].isNew = false  // Clear the "new" flag too
```

## 📱 **Expected Behavior Now**

### ✅ **Position Restoration:**
1. **Scroll down** in timeline
2. **Close app** completely 
3. **Reopen app**
4. **Should automatically scroll back** to your position after ~1 second
5. **Debug log:** `🎯 Attempting position restoration to [postId] after timeline load`

### ✅ **Unread Counter:**
1. **On first launch:** Counter should be **0 or very low** (not 40+)
2. **When new posts arrive:** Counter increases
3. **When scrolling/reading:** Counter decreases as you read new posts
4. **When tapping counter:** Scrolls to top and counter disappears
5. **Debug logs:** `📱 TimelineState: Unread count updated to X (new posts only)`

### ✅ **Debug Logging:**
Now enabled by default to help diagnose issues:
- `🎯 Attempting position restoration to [postId] after timeline load`
- `🎯 No saved position to restore or post not found in timeline`
- `📱 TimelineState: Marked post [id] as read`
- `📱 TimelineState: Unread count updated to X (new posts only)`

## 🔍 **Testing Steps**

1. **Test Position Restoration:**
   - Scroll down, close app, reopen
   - Look for restoration debug messages
   
2. **Test Unread Counter:**
   - Check if it starts at 0 on first launch
   - Scroll through posts and see if it decreases
   - Tap counter to scroll to top and clear it

3. **Check Debug Logs:**
   - Should see detailed logging about what's happening
   - Use logs to identify any remaining issues

The core issues were timing (restoration too early) and logic (all posts marked as new). These fixes address the fundamental problems. 