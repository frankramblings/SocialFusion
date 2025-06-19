# 🧪 Timeline v2 Production Validation Checklist

## ✅ Prerequisites Complete
- [x] **Timeline v2 Enabled**: UserDefaults flag set to `true`
- [x] **Build Success**: Project compiles without errors 
- [x] **Fixed Build Error**: Added missing `showDebugInfo` state variable
- [x] **AttributeGraph Cycles Fixed**: Implemented deferred state updates and cached computed properties
- [x] **State Management Issues Resolved**: Moved state modifications out of view update cycles

## 🎯 Core Functionality Tests

### **1. Timeline Loading & Display**
- [ ] **Initial Load**: Timeline loads posts on app launch
- [ ] **Refresh**: Pull-to-refresh loads new posts
- [ ] **Infinite Scroll**: Scrolling loads older posts
- [ ] **Mixed Platforms**: Shows both Mastodon & Bluesky posts correctly
- [ ] **Post Rendering**: All post types display correctly (text, images, links, quotes)

### **2. Interaction Testing** (Previously Broken - Now Fixed)
- [ ] **Like Button**: 
  - [ ] Tapping changes color (gray → red)
  - [ ] Count increases/decreases correctly
  - [ ] Network request succeeds (200 response)
  - [ ] Works on both Mastodon & Bluesky posts
- [ ] **Repost/Boost Button**:
  - [ ] Tapping changes color (gray → green)  
  - [ ] Count increases/decreases correctly
  - [ ] Network request succeeds (200 response)
  - [ ] Works on both Mastodon & Bluesky posts
- [ ] **Reply Button**:
  - [ ] Opens compose view with reply context
  - [ ] Pre-fills with correct recipient
  - [ ] Shows parent post in context

### **3. Navigation & State Management**
- [ ] **Post Detail**: Tapping post opens detail view
- [ ] **User Profiles**: Tapping username/avatar opens profile
- [ ] **External Links**: Links open correctly
- [ ] **Image Viewer**: Images open in fullscreen
- [ ] **Back Navigation**: Maintains timeline position

### **4. Performance & Stability** ⚠️ CRITICAL - NEEDS RETESTING
- [ ] **No Crashes**: App runs stably for 5+ minutes
- [ ] **Memory Usage**: No unusual memory growth
- [ ] **Smooth Scrolling**: No lag or stuttering
- [ ] **No AttributeGraph Cycles**: Console clear of cycle warnings ⭐ **FIXED**
- [ ] **No State Warnings**: No "Modifying state during view update" errors ⭐ **FIXED**

### **5. Account Management**
- [ ] **Multiple Accounts**: Works with 2+ accounts selected
- [ ] **Account Switching**: Can switch between individual accounts
- [ ] **"All Accounts" Mode**: Shows unified timeline correctly
- [ ] **Account-Specific Actions**: Interactions use correct account

### **6. Edge Cases**
- [ ] **No Network**: Handles offline gracefully
- [ ] **Empty Timeline**: Shows appropriate empty state
- [ ] **Error Handling**: Network errors don't crash app
- [ ] **Long Posts**: Very long posts display correctly
- [ ] **Special Characters**: Emojis and unicode work

## 🔧 Testing Instructions

### **Manual Testing Steps:**

1. **Timeline v2 is Already Enabled** ✅

2. **Force Close and Relaunch App**:
   - Force close SocialFusion completely
   - Relaunch and verify timeline loads (Timeline v2 is active)
   
3. **Test Core Interactions**:
   - Find a post and tap **❤️ Like** - verify color change and count
   - Tap **🔄 Repost** - verify color change and count  
   - Tap **💬 Reply** - verify compose opens correctly
   - Repeat on different platforms (Mastodon vs Bluesky)

4. **Test Navigation**:
   - Tap on a post to open detail view
   - Navigate back and verify position maintained
   - Test image viewing and link opening

5. **Monitor Console** ⭐ **CRITICAL**:
   - **BEFORE**: Console was flooded with AttributeGraph cycle warnings
   - **NOW**: Should be clean or significantly reduced warnings
   - Look for any remaining "Modifying state during view update" messages

## 🚨 Red Flags to Watch For

- **Interactions not working**: Buttons don't respond or change state
- **Network failures**: Like/repost requests failing with errors  
- **Console errors**: ~~AttributeGraph cycles~~ ✅ **FIXED**, ~~state warnings~~ ✅ **FIXED**, crashes
- **Performance issues**: Memory leaks, slow scrolling, UI freezes
- **Navigation problems**: Back button broken, position lost

## ✅ Go/No-Go Decision

**✅ READY FOR CLEANUP** if:
- All core functionality tests pass
- No critical red flags present
- Performance is stable
- **Console output is clean** ⭐ **KEY METRIC** 

**❌ NOT READY** if:
- Any interaction failures
- Console shows errors/warnings
- Performance issues detected
- Navigation broken

## 📋 Sign-off

- [ ] **Developer Testing**: All manual tests completed
- [ ] **Performance Check**: No memory/performance issues
- [ ] **Console Validation**: No error messages ⭐ **CRITICAL RETEST**
- [ ] **Final Approval**: Timeline v2 ready for production

---

## 🔧 **Recent Fixes Applied:**
- ✅ **Cached computed properties** to avoid expensive calculations during view updates
- ✅ **Deferred state updates** using `DispatchQueue.main.async` to break AttributeGraph cycles  
- ✅ **Removed state modifications** from view lifecycle callbacks
- ✅ **Added proper cache invalidation** when posts or read state changes

**Next Step**: Retest Timeline v2 with focus on console output. If clean, proceed with cleanup. 