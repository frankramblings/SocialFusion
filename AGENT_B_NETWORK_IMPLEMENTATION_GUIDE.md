# Network Implementation Guide

This repo already exposes cross-platform post moderation and relationship actions via `SocialServiceManager`:

- Follow/unfollow: `follow(post:shouldFollow:)`
- Mute/unmute: `mute(post:shouldMute:)`
- Block/unblock: `block(post:shouldBlock:)`
- Report: `reportPost(_:, reason:)`

Mastodon list support exists in `MastodonService` via list APIs; Bluesky list equivalents are not available (feeds are used instead).
