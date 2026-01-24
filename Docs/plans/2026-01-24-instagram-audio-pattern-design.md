# Instagram Audio Pattern for Video Playback

## Problem

Video audio is controlled by the device's mute switch. When the user taps unmute on a video, they expect audio to play via system volume regardless of mute switch state.

## Solution

Implement the Instagram pattern:
- Videos autoplay muted (respects silent switch)
- User unmutes a video → audio plays via system volume, ignoring mute switch
- Mute preference persists across videos in the session
- Reset when app goes to background

## Design

### 1. AudioSessionManager

New singleton that manages the shared audio session state.

**File:** `SocialFusion/Services/AudioSessionManager.swift`

```swift
import AVFoundation
import Combine
import UIKit

@MainActor
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()

    @Published private(set) var isInPlaybackMode = false

    private init() {
        setupLifecycleObservers()
    }

    /// Switch to playback mode - audio ignores mute switch
    func activateForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            isInPlaybackMode = true
        } catch {
            // Log error, don't crash
        }
    }

    /// Switch to ambient mode - audio respects mute switch
    func deactivateToAmbient() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            isInPlaybackMode = false
        } catch {
            // Log error, don't crash
        }
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deactivateToAmbient()
        }
    }
}
```

### 2. VideoPlayerView Integration

**Changes to `SmartMediaView.swift`:**

#### VideoPlayerViewModel.toggleMute()

```swift
func toggleMute() {
    guard let player = player else { return }

    if player.isMuted {
        // Unmuting - switch to playback mode
        AudioSessionManager.shared.activateForPlayback()
        player.isMuted = false
    } else {
        // Muting - just mute the player, don't change session
        // (session resets on background, not on individual mute)
        player.isMuted = true
    }
    isMuted = player.isMuted
}
```

#### VideoPlayerView initial mute state

In `onAppear`, check session state:

```swift
.onAppear {
    // Use session-wide preference if in playback mode
    let shouldStartMuted = !AudioSessionManager.shared.isInPlaybackMode
    player.isMuted = shouldStartMuted
    playerModel.isMuted = shouldStartMuted
    // ... rest of onAppear
}
```

#### Remove standalone audio session configuration

Delete `configureAudioSessionForMutedPlayback()` function - this logic moves to `AudioSessionManager`.

### 3. Reset Behavior

**Automatic reset on background:**
- `AudioSessionManager` listens for `willResignActiveNotification`
- Calls `deactivateToAmbient()` automatically
- When user returns, videos start muted (fresh session)

**No navigation-based reset:**
- Keeps implementation simple
- Matches Instagram behavior (only resets on background)

### 4. UI Updates

Mute button icon states:
- Muted: `speaker.slash.fill` (current)
- Unmuted: `speaker.wave.2.fill` (shows audio is active)

## Files Changed

| File | Change |
|------|--------|
| `SocialFusion/Services/AudioSessionManager.swift` | New file |
| `SocialFusion/Views/Components/SmartMediaView.swift` | Integrate AudioSessionManager |

## Not Included

- Volume slider (just mute/unmute, like Bluesky)
- Persistent preference (resets each session, like Instagram)
- Per-video mute memory (session-wide preference only)

## References

- [Twitter/X overrides mute switch when unmuting](https://forums.macrumors.com/threads/why-can-apps-override-the-mute-button.2394570/)
- [Bluesky video audio issues](https://github.com/bluesky-social/social-app/issues/5404)
- Apple docs: AVAudioSession categories (.ambient vs .playback)
