# macOS Native Target Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a native macOS app target to SocialFusion for a read+interact Mac experience (timeline, profiles, search, notifications, like/repost/bookmark).

**Architecture:** New `SocialFusionMac` macOS target in the existing Xcode project. Share source files via target membership. Use `#if os(iOS)` / `#if os(macOS)` conditionals where platform APIs diverge. Mac-specific entry point, sidebar navigation, and toolbar in a new `SocialFusionMac/` folder.

**Tech Stack:** SwiftUI, NavigationSplitView, AppKit (via SwiftUI), existing EmojiText SPM package (macOS-compatible).

---

## Task 1: Create macOS Target in project.yml

**Files:**
- Modify: `project.yml:1-15` (add macOS deployment target)
- Modify: `project.yml:16-117` (add SocialFusionMac target after existing targets)

**Step 1: Add macOS deployment target**

In `project.yml`, the `options` block (lines 1-5) currently sets only iOS. Add macOS:

```yaml
options:
  xcodeVersion: "26.0"
  deploymentTarget:
    iOS: 17.0
    macOS: 14.0
```

**Step 2: Add SocialFusionMac target definition**

After the `SocialFusionTests` target block, add the new macOS target. This shares the `SocialFusion/` source directory but excludes iOS-only files and adds Mac-only files:

```yaml
  SocialFusionMac:
    type: application
    platform: macOS
    sources:
      - path: SocialFusion
        excludes:
          # Files excluded from iOS target (keep these excluded)
          - Networking/NetworkError.swift
          - Views/Utilities/URLServiceWrapper.swift
          - Extensions/NotificationCenter+Extensions.swift
          - Models/TimelineState+Bridge.swift
          - Models/TimelineState+Verification.swift
          - Models/TimelineState+Phase2Verification.swift
          - Views/TestingView.swift
          # iOS-only files excluded from Mac
          - Utilities/HapticEngine.swift
          - ShareAsImage/
          - Intents/
          - SocialFusionApp.swift
      - path: SocialFusionMac
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.socialfusionapp.mac
        PRODUCT_NAME: SocialFusion
        SWIFT_VERSION: 5.0
        DEVELOPMENT_TEAM: $(TEAM_ID)
        INFOPLIST_FILE: SocialFusionMac/Info.plist
        MARKETING_VERSION: 1.0.0
        CURRENT_PROJECT_VERSION: 1
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: SocialFusionMac/SocialFusionMac.entitlements
    dependencies:
      - package: EmojiText
```

**Step 3: Verify the YAML is valid**

Run: `cat project.yml | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin); print('Valid')"` (or just open in Xcode after regenerating).

**Step 4: Commit**

```bash
git add project.yml
git commit -m "feat(mac): add SocialFusionMac target to project.yml"
```

---

## Task 2: Create Mac-Only App Shell Files

**Files:**
- Create: `SocialFusionMac/MacApp.swift`
- Create: `SocialFusionMac/Info.plist`
- Create: `SocialFusionMac/SocialFusionMac.entitlements`

**Step 1: Create the SocialFusionMac directory**

```bash
mkdir -p SocialFusionMac
```

**Step 2: Create MacApp.swift — the macOS entry point**

This mirrors `SocialFusion/SocialFusionApp.swift` (lines 8-170) but uses macOS-compatible APIs. It sets up the same environment objects without iOS-only code (`UIApplication` notifications, `BGTaskScheduler`).

```swift
import SwiftUI

@main
struct SocialFusionMacApp: App {
  @StateObject private var socialServiceManager = SocialServiceManager()
  @StateObject private var appVersionManager = AppVersionManager()
  @StateObject private var oauthManager = OAuthManager()
  @StateObject private var postNavigation = PostNavigationEnvironment()
  @StateObject private var draftStore = DraftStore()
  @StateObject private var chatStreamService = ChatStreamService()

  var body: some Scene {
    WindowGroup {
      MacContentView()
        .environmentObject(socialServiceManager)
        .environmentObject(appVersionManager)
        .environmentObject(oauthManager)
        .environmentObject(postNavigation)
        .environmentObject(NotificationManager.shared)
        .environmentObject(EdgeCaseHandler.shared)
        .environmentObject(draftStore)
        .environmentObject(chatStreamService)
        .environmentObject(CrashReportingService.shared)
        .onOpenURL { url in
          handleIncomingURL(url)
        }
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 1100, height: 750)

    Settings {
      SettingsView()
        .environmentObject(socialServiceManager)
        .environmentObject(appVersionManager)
    }
  }

  private func handleIncomingURL(_ url: URL) {
    if url.scheme == "socialfusion" {
      if url.host == "oauth-callback" {
        oauthManager.handleCallback(url: url)
      }
    }
  }
}
```

**Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>socialfusion</string>
            </array>
            <key>CFBundleURLName</key>
            <string>com.socialfusionapp.mac</string>
        </dict>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
```

**Step 4: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.socialfusionapp.mac</string>
    </array>
</dict>
</plist>
```

**Step 5: Commit**

```bash
git add SocialFusionMac/
git commit -m "feat(mac): add macOS app shell — entry point, Info.plist, entitlements"
```

---

## Task 3: Create MacContentView with NavigationSplitView Sidebar

**Files:**
- Create: `SocialFusionMac/MacContentView.swift`
- Create: `SocialFusionMac/MacSidebarView.swift`

**Step 1: Create MacContentView.swift**

This is the main container using `NavigationSplitView`. It replaces the iOS `TabView` from `ContentView.swift`.

```swift
import SwiftUI

struct MacContentView: View {
  @EnvironmentObject var socialServiceManager: SocialServiceManager
  @State private var selectedSection: SidebarSection = .home
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      MacSidebarView(selection: $selectedSection)
    } detail: {
      detailView
    }
    .frame(minWidth: 800, minHeight: 600)
    .navigationTitle(selectedSection.title)
  }

  @ViewBuilder
  private var detailView: some View {
    switch selectedSection {
    case .home:
      ConsolidatedTimelineView()
    case .notifications:
      NotificationsView()
    case .search:
      SearchView()
    case .profile:
      if let account = socialServiceManager.activeAccounts.first {
        ProfileView(account: account)
      } else {
        Text("No account selected")
      }
    case .account(let accountId):
      if let account = socialServiceManager.activeAccounts.first(where: { $0.id == accountId }) {
        AccountTimelineView(account: account)
      }
    }
  }
}

enum SidebarSection: Hashable {
  case home
  case notifications
  case search
  case profile
  case account(String)

  var title: String {
    switch self {
    case .home: return "Home"
    case .notifications: return "Notifications"
    case .search: return "Search"
    case .profile: return "Profile"
    case .account: return "Account"
    }
  }
}
```

**Step 2: Create MacSidebarView.swift**

```swift
import SwiftUI

struct MacSidebarView: View {
  @EnvironmentObject var socialServiceManager: SocialServiceManager
  @Binding var selection: SidebarSection

  var body: some View {
    List(selection: $selection) {
      Section("Timelines") {
        Label("Home", systemImage: "house")
          .tag(SidebarSection.home)
      }

      if !socialServiceManager.activeAccounts.isEmpty {
        Section("Accounts") {
          ForEach(socialServiceManager.activeAccounts, id: \.id) { account in
            Label {
              Text(account.displayName ?? account.username)
            } icon: {
              Image(systemName: account.platform == .mastodon ? "elephant" : "bird")
            }
            .tag(SidebarSection.account(account.id))
          }
        }
      }

      Section {
        Label("Notifications", systemImage: "bell")
          .tag(SidebarSection.notifications)
        Label("Search", systemImage: "magnifyingglass")
          .tag(SidebarSection.search)
        Label("Profile", systemImage: "person.circle")
          .tag(SidebarSection.profile)
      }
    }
    .listStyle(.sidebar)
    .frame(minWidth: 200)
  }
}
```

**Step 3: Commit**

```bash
git add SocialFusionMac/MacContentView.swift SocialFusionMac/MacSidebarView.swift
git commit -m "feat(mac): add MacContentView with NavigationSplitView sidebar"
```

---

## Task 4: Gate Compile Blockers — AVAudioSession

**Files:**
- Modify: `SocialFusion/Views/Components/SmartMediaView.swift:1437-1453,1495-1522`
- Modify: `SocialFusion/Views/Components/AudioPlayerView.swift:282-292,294-334`

These files use `AVAudioSession` which is unavailable on macOS. Wrap the calls in `#if os(iOS)`.

**Step 1: Gate AVAudioSession in SmartMediaView.swift**

At line 1437, the free function `configureAudioSessionForMutedPlayback()`:
```swift
fileprivate func configureAudioSessionForMutedPlayback() {
  #if os(iOS)
  let audioSession = AVAudioSession.sharedInstance()
  // ... existing code ...
  #endif
}
```

At lines 1495-1505, the `VideoPlayerViewModel` method `configureAudioSessionForMutedPlayback()`:
```swift
private func configureAudioSessionForMutedPlayback() {
  #if os(iOS)
  // ... existing code ...
  #endif
}
```

At lines 1507-1522, `configureAudioSessionForUnmutedPlayback()`:
```swift
private func configureAudioSessionForUnmutedPlayback() {
  #if os(iOS)
  // ... existing code ...
  #endif
}
```

**Step 2: Gate AVAudioSession and MediaPlayer in AudioPlayerView.swift**

At line 3, gate the import:
```swift
#if os(iOS)
import MediaPlayer
#endif
```

At lines 282-292, `configureAudioSession()`:
```swift
private func configureAudioSession() {
  #if os(iOS)
  // ... existing code ...
  #endif
}
```

At lines 294-321, `setupRemoteControl()`:
```swift
private func setupRemoteControl() {
  #if os(iOS)
  // ... existing code ...
  #endif
}
```

At lines 323-334, `updateNowPlayingInfo()`:
```swift
private func updateNowPlayingInfo() {
  #if os(iOS)
  // ... existing code ...
  #endif
}
```

**Step 3: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Views/Components/SmartMediaView.swift SocialFusion/Views/Components/AudioPlayerView.swift
git commit -m "fix(mac): gate AVAudioSession and MediaPlayer behind #if os(iOS)"
```

---

## Task 5: Gate Compile Blockers — BGAppRefreshTask

**Files:**
- Modify: `SocialFusion/Services/NotificationManager.swift:1,88-126`

**Step 1: Gate background task registration and scheduling**

At line 1, make the import conditional:
```swift
#if os(iOS)
import BackgroundTasks
#endif
```

Gate the three methods (lines 88-126):
```swift
#if os(iOS)
func registerBackgroundTask() {
  // ... existing code (lines 88-96) ...
}

func scheduleBackgroundRefresh() {
  // ... existing code (lines 98-108) ...
}

private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
  // ... existing code (lines 110-126) ...
}
#endif
```

**Step 2: Gate callers of registerBackgroundTask**

In `SocialFusionApp.swift` line 93, the call `notificationManager.registerBackgroundTask()` needs guarding:
```swift
#if os(iOS)
notificationManager.registerBackgroundTask()
#endif
```

Check `SettingsView.swift` for any references to background refresh scheduling and gate those too.

**Step 3: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Services/NotificationManager.swift SocialFusion/SocialFusionApp.swift
git commit -m "fix(mac): gate BGAppRefreshTask behind #if os(iOS)"
```

---

## Task 6: Gate Compile Blockers — HapticEngine

**Files:**
- Modify: `SocialFusion/Utilities/HapticEngine.swift:1-74`

The entire file uses iOS-only `UI*FeedbackGenerator` APIs. Rather than excluding the file from the Mac target (which would break every call site), wrap the implementations so they become no-ops on macOS.

**Step 1: Add platform conditionals**

```swift
#if os(iOS)
import UIKit
#endif

enum HapticEngine {
  // ... cases stay the same ...

  func trigger() {
    #if os(iOS)
    switch self {
    // ... existing switch body ...
    }
    #endif
  }

  static func prepare(_ pattern: HapticEngine) {
    #if os(iOS)
    switch pattern {
    // ... existing switch body ...
    }
    #endif
  }
}
```

This way, call sites compile on both platforms — haptics simply do nothing on Mac.

**Step 2: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/Utilities/HapticEngine.swift
git commit -m "fix(mac): make HapticEngine no-op on macOS"
```

---

## Task 7: Gate UIKit Dependencies — ConnectionManager, LiquidGlass, ContentView

**Files:**
- Modify: `SocialFusion/Networking/ConnectionManager.swift:3,21,42-61,282-296`
- Modify: `SocialFusion/Views/Components/LiquidGlassConfiguration.swift:67-107,315`
- Modify: `SocialFusion/ContentView.swift:493-537,862-880`

**Step 1: Gate ConnectionManager background task and notifications**

Line 3: Make UIKit import conditional and add AppKit:
```swift
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
```

Line 21: Gate the background task identifier:
```swift
#if os(iOS)
private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif
```

Lines 42-61 (`setupNotifications`): Gate `UIApplication` notification subscriptions:
```swift
private func setupNotifications() {
  #if os(iOS)
  NotificationCenter.default.addObserver(/* UIApplication.didEnterBackground */)
  NotificationCenter.default.addObserver(/* UIApplication.willEnterForeground */)
  NotificationCenter.default.addObserver(/* UIApplication.willTerminate */)
  #endif
}
```

Lines 282-296: Gate `beginBackgroundTaskIfNeeded` and `endBackgroundTaskIfNeeded`:
```swift
#if os(iOS)
private func beginBackgroundTaskIfNeeded() { /* existing code */ }
private func endBackgroundTaskIfNeeded() { /* existing code */ }
#else
private func beginBackgroundTaskIfNeeded() {}
private func endBackgroundTaskIfNeeded() {}
#endif
```

**Step 2: Gate LiquidGlassConfiguration appearance proxies**

Lines 67-75 (`configureNavigationBarAppearance`): Wrap body in `#if os(iOS)`.
Lines 77-107 (`configureTabBarAppearance`): Wrap body in `#if os(iOS)`.
Line 315 (`UIDevice.current.systemVersion`): Wrap in `#if os(iOS)`.

**Step 3: Gate ContentView TabBarDelegate**

Lines 493-537 (`setupTabBarDelegate`, `findTabBarController`): Wrap in `#if os(iOS)`.
Lines 862-880 (`TabBarDelegate` class): Wrap in `#if os(iOS)`.
Line 111 (call to `setupTabBarDelegate()`): Wrap in `#if os(iOS)`.

**Step 4: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 5: Commit**

```bash
git add SocialFusion/Networking/ConnectionManager.swift SocialFusion/Views/Components/LiquidGlassConfiguration.swift SocialFusion/ContentView.swift
git commit -m "fix(mac): gate UIKit-specific APIs behind #if os(iOS)"
```

---

## Task 8: Fix Platform-Aware User Agent Strings

**Files:**
- Modify: `SocialFusion/Networking/NetworkConfig.swift:2,25`
- Modify: `SocialFusion/Services/AuthenticatedVideoAssetLoader.swift:229-230,714-715`

**Step 1: Fix NetworkConfig.swift**

Replace line 2 and line 25:
```swift
#if os(iOS)
import UIKit
#endif
import Foundation

// ...

#if os(iOS)
static let userAgent = "SocialFusion/1.0 iOS/\(UIDevice.current.systemVersion) (iPhone)"
#elseif os(macOS)
static let userAgent = "SocialFusion/1.0 macOS/\(ProcessInfo.processInfo.operatingSystemVersionString)"
#endif
```

**Step 2: Fix AuthenticatedVideoAssetLoader.swift**

At lines 229-230 and 714-715, replace the hardcoded user agent with a reference to `NetworkConfig.userAgent` or add inline conditionals:
```swift
#if os(iOS)
let userAgent = "SocialFusion/1.0 (iPhone; iOS \(UIDevice.current.systemVersion)) AppleWebKit/605.1.15"
#elseif os(macOS)
let userAgent = "SocialFusion/1.0 (Macintosh; \(ProcessInfo.processInfo.operatingSystemVersionString)) AppleWebKit/605.1.15"
#endif
```

**Step 3: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 4: Commit**

```bash
git add SocialFusion/Networking/NetworkConfig.swift SocialFusion/Services/AuthenticatedVideoAssetLoader.swift
git commit -m "fix(mac): platform-aware user agent strings"
```

---

## Task 9: Fix UIScreen.main References

**Files:**
- Modify: `SocialFusion/Views/Components/ParallaxMediaModifier.swift:24`
- Modify: `SocialFusion/Views/Components/SmartMediaView.swift:44,186`
- Modify: various other files with `UIScreen.main` references

`UIScreen.main` is deprecated on iOS 16+ and unavailable on macOS. The fix pattern is:

**Step 1: Fix ParallaxMediaModifier.swift**

Line 24 — replace the static `UIScreen.main` with a platform conditional:
```swift
#if os(iOS)
private static let screenMidY = UIScreen.main.bounds.height / 2
#elseif os(macOS)
private static let screenMidY = (NSScreen.main?.frame.height ?? 800) / 2
#endif
```

**Step 2: Fix SmartMediaView.swift**

Line 44:
```swift
#if os(iOS)
let screenBounds = UIScreen.main.bounds
#elseif os(macOS)
let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
#endif
```

Line 186:
```swift
#if os(iOS)
let adaptiveMaxHeight = maxHeight ?? UIScreen.main.bounds.height * 0.8
#elseif os(macOS)
let adaptiveMaxHeight = maxHeight ?? (NSScreen.main?.frame.height ?? 800) * 0.8
#endif
```

**Step 3: Fix remaining UIScreen.main references**

Apply the same pattern to these files (replace `UIScreen.main.bounds` with `NSScreen.main?.frame` on macOS):
- `ShareAsImage/ShareImageRenderer.swift` — lines 53, 81, 106, 130, 151 (scale references). These are in `ShareAsImage/` which is excluded from the Mac target, so **no changes needed**.
- `Views/AccountTimelineView.swift:329`
- `Views/ConsolidatedTimelineView.swift:174,176`
- `Views/Components/UnifiedMediaGridView.swift:99`
- `Views/Components/PostCardView.swift:620`
- `Views/Components/PostDetailView.swift:1099`
- `Views/Components/FullscreenMediaView.swift:211`
- `Views/Components/GIFUnfurlContainer.swift:226`
- `Views/Components/VideoVisibilityTracker.swift:39`
- `Views/Components/LiquidGlassComponents.swift:76-77`

For each, wrap in `#if os(iOS)` / `#elseif os(macOS)` with `NSScreen.main?.frame`.

**Step 4: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 5: Commit**

```bash
git add -A
git commit -m "fix(mac): replace UIScreen.main with platform-aware screen bounds"
```

---

## Task 10: Gate SocialFusionApp.swift iOS-Only Code

**Files:**
- Modify: `SocialFusion/SocialFusionApp.swift:44,48,93`

**Step 1: Gate UIApplication notification observers**

Lines 44 and 48 use `UIApplication.willResignActiveNotification` and `UIApplication.willTerminateNotification`. Wrap these:

```swift
#if os(iOS)
NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, ...)
NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, ...)
#elseif os(macOS)
NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, ...)
NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, ...)
#endif
```

Line 93 (`registerBackgroundTask`) was already handled in Task 5.

**Step 2: Verify iOS build still compiles**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 3: Commit**

```bash
git add SocialFusion/SocialFusionApp.swift
git commit -m "fix(mac): gate UIApplication notifications, add NSApplication equivalents"
```

---

## Task 11: Add Keyboard Shortcuts and Menu Commands

**Files:**
- Create: `SocialFusionMac/MacMenuCommands.swift`

**Step 1: Create menu commands**

```swift
import SwiftUI

struct MacMenuCommands: Commands {
  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Refresh Timeline") {
        NotificationCenter.default.post(name: .refreshTimeline, object: nil)
      }
      .keyboardShortcut("r", modifiers: .command)
    }

    CommandGroup(replacing: .help) {
      Link("SocialFusion Help", destination: URL(string: "https://socialfusion.app/help")!)
    }
  }
}

extension Notification.Name {
  static let refreshTimeline = Notification.Name("refreshTimeline")
}
```

**Step 2: Add Commands to MacApp.swift**

Add `.commands { MacMenuCommands() }` to the `WindowGroup` scene in `MacApp.swift`.

**Step 3: Add keyboard shortcuts to MacContentView**

Add keyboard shortcuts to the detail view for post navigation:
```swift
.onKeyPress("j") { /* select next post */ return .handled }
.onKeyPress("k") { /* select previous post */ return .handled }
```

Or use `.keyboardShortcut` modifiers on the sidebar items:
```swift
Label("Home", systemImage: "house")
  .tag(SidebarSection.home)
  .keyboardShortcut("1", modifiers: .command)
```

**Step 4: Commit**

```bash
git add SocialFusionMac/MacMenuCommands.swift SocialFusionMac/MacApp.swift SocialFusionMac/MacContentView.swift
git commit -m "feat(mac): add menu commands and keyboard shortcuts"
```

---

## Task 12: Regenerate Xcode Project and First Mac Build

**Step 1: Regenerate project from project.yml**

Run: `xcodegen generate`

If xcodegen is not installed locally, you can modify `project.pbxproj` directly in Xcode by adding the macOS target through the UI. But `project.yml` is the source of truth for CI.

**Step 2: Attempt first macOS build**

Run: `xcodebuild build -scheme SocialFusionMac -destination 'platform=macOS' 2>&1 | head -100`

**Step 3: Fix any remaining compile errors**

Likely issues:
- Missing `import AppKit` in files that use `NSScreen`
- Additional `UIKit`-only APIs not caught in the audit (iterate on these)
- Availability checks using `@available(iOS 18.0, *)` — need `|| macOS 15.0` equivalents

For each error:
1. Identify the iOS-only API
2. Gate with `#if os(iOS)` / `#elseif os(macOS)` providing a macOS equivalent or no-op
3. Rebuild and repeat

**Step 4: Verify iOS build still works**

Run: `xcodebuild build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`

**Step 5: Commit all remaining fixes**

```bash
git add -A
git commit -m "feat(mac): first successful macOS build"
```

---

## Task 13: Polish — Window Sizing, Toolbar, and Sidebar Refinement

**Files:**
- Modify: `SocialFusionMac/MacApp.swift`
- Modify: `SocialFusionMac/MacContentView.swift`
- Modify: `SocialFusionMac/MacSidebarView.swift`

**Step 1: Refine window configuration**

In `MacApp.swift`, ensure proper window frame management:
```swift
WindowGroup {
  MacContentView()
    // ... environment objects ...
}
.defaultSize(width: 1100, height: 750)
.windowResizability(.contentSize)
```

**Step 2: Add toolbar to MacContentView**

```swift
.toolbar {
  ToolbarItem(placement: .automatic) {
    Button(action: { /* refresh */ }) {
      Image(systemName: "arrow.clockwise")
    }
  }
}
.searchable(text: $searchText, placement: .toolbar)
```

**Step 3: Refine sidebar with account avatars**

Update `MacSidebarView` to show platform badges (Mastodon elephant, Bluesky butterfly) and account avatars using `AsyncImage`.

**Step 4: Test window resizing**

Manually verify:
- Window respects minimum size (800x600)
- Timeline content reflows on resize
- Sidebar toggle works (standard macOS sidebar button)
- No layout breakage at various sizes

**Step 5: Commit**

```bash
git add SocialFusionMac/
git commit -m "feat(mac): polish window sizing, toolbar, and sidebar"
```

---

## Task 14: Verify Full Build — Both Platforms

**Step 1: Clean build iOS**

Run: `xcodebuild clean build -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet`
Expected: BUILD SUCCEEDED with 0 errors.

**Step 2: Clean build macOS**

Run: `xcodebuild clean build -scheme SocialFusionMac -destination 'platform=macOS' -quiet`
Expected: BUILD SUCCEEDED with 0 errors.

**Step 3: Run macOS app in simulator/locally**

Run the SocialFusionMac scheme in Xcode targeting "My Mac". Verify:
- App launches with sidebar visible
- Sidebar sections are selectable
- Timeline loads posts (with an active account)
- Posts render correctly with media
- Like/repost/bookmark buttons are functional
- Settings window opens via Cmd+,
- Window resizes properly

**Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(mac): resolve remaining build issues for both platforms"
```

---

## Dependency Graph

```
Task 1 (project.yml) ──┐
                        ├── Task 12 (first build)
Task 2 (app shell) ────┤
Task 3 (sidebar) ──────┘
                            │
Task 4 (AVAudioSession) ───┤
Task 5 (BGTask) ───────────┤
Task 6 (HapticEngine) ─────┤
Task 7 (UIKit gates) ──────┼── Task 12 (first build) ── Task 13 (polish) ── Task 14 (verify)
Task 8 (user agents) ──────┤
Task 9 (UIScreen) ─────────┤
Task 10 (SocialFusionApp) ─┤
Task 11 (menu commands) ───┘
```

Tasks 1-3 create the Mac target structure. Tasks 4-11 can be done in parallel — they're independent platform compatibility fixes. Task 12 attempts the first build and iterates. Tasks 13-14 are polish and verification.
