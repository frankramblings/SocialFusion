# SocialFusion

A unified social media client for Mastodon and Bluesky, built with SwiftUI.

SocialFusion brings your federated feeds into one clean, modern interface. Browse a unified timeline, interact with posts across networks, and publish to multiple platforms — all from a single app.

<div align="center">
  <img src="Github%20header.png" alt="SocialFusion Header">
</div>

## Features

- **Unified Timeline** — Mastodon and Bluesky posts in a single, chronological feed
- **Multi-Account** — Add multiple accounts across platforms and switch between them
- **Cross-Platform Posting** — Compose and publish to Mastodon, Bluesky, or both at once
- **Rich Media** — Images, videos, GIFs, audio, and YouTube embeds with fullscreen viewing
- **Cinematic Profiles** — Parallax banner, 3D tilt effects, docking avatar, and tabbed content
- **Timeline Filtering** — All posts, Mastodon only, Bluesky only, or custom combinations
- **Link Previews** — Inline URL preview cards with caching
- **Draft Recovery** — Auto-saved drafts so you never lose a post in progress
- **Accessibility** — VoiceOver, Dynamic Type, and Reduce Motion support throughout

## Requirements

- iOS 17+
- Xcode 15+

## Getting Started

1. Clone the repository
2. Open `SocialFusion.xcodeproj` in Xcode
3. Select the **SocialFusion** scheme
4. Build and run on a simulator or device (Cmd+R)

## Architecture

SocialFusion uses a protocol-driven MVVM architecture:

- **Service Layer** — `SocialServiceManager` coordinates account management, timeline fetching, caching, and post operations. Platform-specific API clients conform to shared protocols.
- **State Management** — Controllers for source-of-truth state, view models for presentation logic, and stores for cross-cutting concerns like post actions and drafts.
- **Networking** — Centralized `ConnectionManager` with rate limiting, circuit breaker pattern, and automatic token refresh.
- **UI** — SwiftUI-first, with UIKit only where necessary. Emphasis on fluid animations and graceful degradation.

## Roadmap

- Additional federated networks
- Pinnable timelines (Mastodon lists, Bluesky feeds, custom groups)
- iPad and Mac optimizations
- Push notifications

## License

All rights reserved.

---

Made for the open social web.
