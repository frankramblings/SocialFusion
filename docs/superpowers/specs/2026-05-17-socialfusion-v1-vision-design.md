# SocialFusion v1.0 — Vision & Design

**Status:** Draft for review
**Date:** 2026-05-17
**Author:** Frank Emanuele (with Claude collaboration)
**Context:** Competitive response to Indigo (Soapbox Software, launched 2026-05-12); strategic positioning for SocialFusion's v1.0 release.

---

## Thesis

> SocialFusion is a single home for **Bluesky, Mastodon, and the federated networks beyond** — built on the premise that **separate networks remain separate**, but the **people who span them** and the **conversations that bridge them** are one.

Three claims compressed into one sentence:

- **Single home.** Not "client," not "aggregator" — a place you live, with rooms that have distinct characters but one front door.
- **Separate networks remain separate.** Mastodon's culture is not Bluesky's culture; the app respects that. We don't flatten identities or pretend the networks are interchangeable. Generalizes from "two" so the thesis still holds when Threads, Nostr, or whatever federates next is added.
- **People and conversations are one.** When the same human is identifiable across networks, their profile unifies. When the same moment exists on both networks, the conversation around it unifies. Identity and conversation are the two pillars of what we unify; everything else stays plural.

---

## Principles

Seven commitments the app holds itself to across every surface and feature.

### 1. The conversation is the unit of attention.
The Fuse (Layer 4). Every surface — timeline, thread, reply composer, notifications, watch list — treats **the conversation** as the larger thing posts belong to. Posts are network-specific; conversations are not.

### 2. Identity is whole, not partitioned.
**Your** accounts — however many, on however many networks — are *all active at once*, never one-at-a-time. **Their** profiles unify when we can recognize the same human across networks (verified link, matching handle conventions, or user confirmation). Accounts persist; identity unifies.

### 3. You shape the lens. We don't.
Pinnable timelines, opinionated filters you control, no opaque "for you" algorithm. Whatever shaping happens is glass-box — you see the rule and can edit it. The app holds the lens; you point it.

### 4. Native craft is the floor, not the goal.
100% SwiftUI. Animation as language, not decoration. Haptics that mean something. We do not try to out-design Indigo — we hold the line for *our* taste. The Apple-OG, Tapbots / IconFactory / Studio Neat lineage, applied honestly.

### 5. Accessibility is first-class.
Dual-coded network indicators (shape-coded silhouettes via `PlatformLogoBadge`, paired with color, paired with high-contrast Settings toggle). VoiceOver, Dynamic Type, reduce-motion, keyboard nav — not afterthoughts. The Six Colors colorblind paragraph will not be written about us.

### 6. Open by default — code, data, trust.
MIT license. No backend server. Credentials in iOS Keychain, never sent to anyone. Source is auditable, contributable, forkable. The federated movement deserves a client that lives by the same values it does.

### 7. We work for the user, not the advertiser.
No ads. No surveillance. No data harvesting. The **basics of being social** — reading, posting, replying, liking, reposting, DMing — will never be paywalled. The long-term monetization model isn't finalized; any future paid features will be *clear, optional, and additive* — value the app gives you, not gates on the things you'd otherwise be doing anyway.

---

## Audience

### Bullseye
**The dual-network believer.** Already on both networks. Switches apps constantly. Reads MacStories or Six Colors. Cares enough about how software is made to notice when it's done right. Wants the federated web to *feel* like home, not work.

### Adjacent — high overlap, lower commitment
- **The bridge user.** Anchored on one network (mostly Mastodon, or mostly Bluesky), curious about the other. Doesn't want a second app to maintain a part-time presence.
- **The Apple-quality aficionado.** Came for the craft, stays for the unification. May not be a federated power-user yet — but recognizes a well-made app and gets pulled in.
- **The cross-posting creator.** Posts to both networks for reach. Wants edits / replies / deletions handled coherently. Croissant solved their publish problem; SocialFusion solves the after-publish problem.

### Secondary ring — drawn by values
- **The recovering corporate-social user.** Left Twitter/X. Has accounts on both Bluesky and Mastodon out of caution, doesn't actively manage them. SocialFusion makes consolidating effortless.
- **The open-web believer.** May not be a heavy social user. Wants tools aligned with their values: no ads, no surveillance, MIT license, no backend.

### Not for
Single-network casual users (Ivory or the official apps are fine). Read-only users (Tapestry). Android-primary users (Openvibe).

---

## Positioning

The strategic claim, in one square: **the top-right quadrant of the 2x2 — multi-network full social + open, user-aligned model — is empty except for us.**

Two axes:

- **X — Network coverage / interaction depth:** single-network ←→ multi-network full social
- **Y — Trust model:** closed-source, paywall on basics ←→ open by default, user-aligned

Where everyone sits:

| App | Networks | Posting | Native Apple | Open source | Multi-account | Pricing |
|---|---|---|---|---|---|---|
| **SocialFusion** | Bluesky, Mastodon (+ future) | Full · cross-post · echo reply · Fuse | 100% SwiftUI | MIT | All accounts active | Free for basics; advanced features TBD |
| Indigo | Bluesky, Mastodon | Full · cross-post · dedup | Yes | No | One active per net | $4.99/mo (paywalls like) |
| Ivory | Mastodon only | Full | Yes (UIKit) | No | Yes | $1.99/mo |
| Ice Cubes | Mastodon only | Full | SwiftUI | AGPL | Yes | Free |
| Tapestry | BSky, Mastodon, RSS, YT, Tumblr… | Read-only | Yes | No | N/A | $1.99/mo |
| Croissant | Bluesky, Mastodon, Threads | Post-only (no timeline) | Yes | No | Yes | Paid |
| Openvibe | BSky, Mastodon, Nostr, Threads | Full · cross-post | Cross-platform | No | Yes | Free |

Indigo is structurally close on networks but sits across the y-axis line (closed-source, paywall on liking). Nobody else is even in the right hemisphere.

---

## The Fuse — Signature Breakthrough

### The thesis behind the breakthrough

Indigo's cross-post dedup is a *visual* merge of two posts. The posts stay separate underneath. The conversations stay separate forever. Their dedup is a presentation hint on a card.

SocialFusion's wedge: **posts are network-specific, but conversations are not.** When the same author posts the same content to both networks within a small time window, SocialFusion identifies the moment, stitches the conversation, and treats it as one thread with replies that happen to come from different networks.

This is architecture, not presentation. Indigo would have to rewrite their reply model to copy it.

### Five moves

1. **Detection (data layer)** — A heuristic that flags two posts as the same moment from the same author: matching content (after light normalization for cross-poster quirks), close timestamps (configurable window, default ≈10 min), confirmed-same-author via the merged-identity logic in Principle 2. Results stored as moment IDs that the rest of the app reads.

2. **Unified conversation view (consumption)** — Tap a Fused post and you don't get "the Mastodon detail" or "the Bluesky detail." You get the conversation: replies from both networks merged into a single chronological stream, each reply tagged with a small network chip (using the `PlatformLogoBadge` for shape-coded accessibility). Network preserved as metadata on each reply; conversation is the unit.

3. **Echo reply (production)** — A per-post composer with toggles for each network. The Send button color **is** the policy:
   - "Reply to both" (purple → cyan → blue gradient)
   - "Reply on Mastodon" (purple)
   - "Reply on Bluesky" (blue)

   Live character counts for both networks (dimmed when only one is selected). Reply and new-post share one composer model.

   Onboarding asks: *Echo replies by default?* with a toggle (default ON) and a "Not now — I'll choose each time" secondary action. Settings keeps a global default radio: Echo on / Echo off / Choose each time.

4. **Watch a conversation (persistence)** — A subscribe action on any post. New replies on either network ping you. Watched conversations live in a dedicated view. Cross-network thread-following the way email and Slack already let you do for single channels — but applied across networks.

5. **The Fused glyph (visual identity)** — A miniature of the SocialFusion logo: two overlapping circles (Mastodon `#8A63FF` purple + Bluesky `#0096FF` blue) with a cyan lens (`#1EE7FF`).

   - **Primary state (A):** the filled Venn glyph, dormant. Used wherever a Fused post appears (timeline, thread header, share previews).
   - **Just-synced state (D):** the same Venn with the launch-animation bloom — pulses briefly when SocialFusion has just confirmed a new Fused moment, then settles back to A.

   This intentionally echoes the launch animation: app launch and post-fusion are the same gesture at two scales.

### What's deferred to v1.x in this surface

- **Glass-box filter editor** — the principled "you shape the lens" power-user UI (full rule editor). v1.0 ships pinnable timelines + account-group pins as the entry point.
- **Cross-device watched-conversation sync** — depends on iCloud KVS budget; if it fits, ships in v1.0, otherwise v1.1.
- **Echo-aware delete/edit propagation** — if a Fused post is deleted on one side, optionally propagate the action. v1.x.

---

## v1.0 Scope

### The five-headline story (App Store screenshots)

1. Unified timeline across both networks
2. The Fuse: one conversation, two networks
3. Real multi-account — all active at once
4. Pinnable timelines you shape yourself
5. Free for the basics. Always. MIT.

### Polish & ship (already built)

- Unified timeline (Mastodon + Bluesky) with per-network filters
- Multi-account, all accounts active simultaneously
- Like / reply / repost / quote with optimistic updates + rollback
- Compose with cross-post, drafts, autocomplete (mentions/hashtags)
- Link previews, media gallery, fullscreen viewer (images, videos, YouTube, audio)
- Profile view (cinematic scroll, parallax, Posts / Replies / Media tabs)
- In-conversation search with highlight + jump navigation
- Notifications (unified, background polling)
- Position restoration, draft auto-save
- Onboarding carousel + launch animation (already echoes the Fused glyph)
- OAuth (Mastodon), session tokens (Bluesky), token refresh, Keychain credentials
- Accessibility floor: VoiceOver, Dynamic Type, reduce-motion plumbing, `PlatformLogoBadge` shape-coded indicators

### New for v1.0 (must build before launch)

| Item | Notes |
|---|---|
| **Fuse detection layer** | Heuristic implementation + moment ID storage. Test corpus of 100+ real cross-posts. |
| **Unified conversation view** | Tap a Fused post → merged replies, network-tagged via `PlatformLogoBadge`. |
| **Per-post echo composer** | Both networks shown as toggles; Send-button-as-policy with gradient/color states. |
| **Onboarding echo ask** | "Echo by default?" toggle + "Not now — I'll choose each time" secondary. |
| **Fused glyph (A→D bloom)** | Filled Venn dormant; bloom animation on first-sync; reuses launch-animation language. |
| **Watch a conversation** | Subscribe + watched-threads view. Push notifications cross-network. |
| **Merged profile cards** | When same human is recognizable on both networks; user-confirmable. |
| **Pinnable timelines (medium depth)** | Pin Mastodon Lists + Bluesky Lists/Feeds; account-group pins (e.g. "just work accounts"). Full filter editor deferred to v1.1. |
| **Dual-coded indicator audit + high-contrast toggle** | Every network-signaling surface uses `PlatformLogoBadge` or equivalent shape-coded element. Settings "High-contrast network indicators" toggle. |
| **Timeline search** | Two-layer: client-side filter through loaded buffer (<100ms) + server-side query streaming below (<500ms). Pinned-timeline scoping. |
| **Cross-device timeline-position sync** | iCloud Key-Value Store (`NSUbiquitousKeyValueStore`). Per account, per timeline, last-read post ID + timestamp. Keeps "no backend server" honest. |
| **Error UI feedback** | Toast/banner for timeline errors. Resolves open TODOs in `TimelineViewModel.swift:499, 553`. |
| **Quote post fallback polish** | Resolves known issue with `FetchQuotePostView`. |
| **Accessibility audit pass** | Colorblind-simulator screenshot check, VoiceOver run-through, Dynamic Type pass, keyboard nav on iPadOS. External-tester optional. |

### In the box, quietly (ships but doesn't headline)

- **Direct Messages** — full streaming, group chats, reactions (Bluesky), edits/deletion (Mastodon), typing indicators, read receipts. Substantial vs. Indigo's basic DM; held in reserve in case the gap becomes visible chatter.
- **Share Extension** — share from other apps into SocialFusion composer.
- **Share as Image** — post screenshot/export.
- **App Intents / Siri Shortcuts** — present, not foregrounded.

### Defer to v1.x

- **macOS app** — Indigo ships day-one Mac; SocialFusion holds iOS/iPadOS at v1.0. Reasons: focuses scope, lets Mac get design attention rather than a rushed Catalyst port. Target: v1.1.
- **Threads support** — Meta API can't expose timeline reading. Thesis ("federated networks beyond") leaves the door open.
- **Full glass-box filter editor** — pinnable timelines (medium depth) is the v1.0 entry point.
- **Custom themes / icon packs** — candidate paid extras for later.
- **Echo-aware delete/edit propagation** — see "deferred in the Fuse surface" above.

### Strategic decisions (locked)

| # | Question | Answer |
|---|---|---|
| Q1 | macOS at v1.0? | Defer to v1.1. iOS/iPadOS only at launch. |
| Q2 | DMs — headline, quiet, or cut? | Ship quietly. |
| Q3 | Pinnable timelines depth at v1.0? | Medium — existing lists/feeds + account groups. Full editor at v1.1. |
| Q4 | Formal accessibility audit before v1.0? | Yes, budget the time. |

---

## Indigo Gap Map

Each confirmed Indigo v1.0 gap paired with the specific SocialFusion response. Sourced from Six Colors (Jason Snell), Pixel Envy (Nick Heer), App Store user reviews, and the Indigo competitive analysis (`docs/competitive/indigo-analysis.md`).

### Beats — places we exceed Indigo

| Gap | SocialFusion response |
|---|---|
| **Only one active account per network** | Real multi-account, all active simultaneously. Already built. Layer 2 headline. |
| **Paywall on basic interaction** ($4.99/mo to like) | Basic interaction always free. Principle 7. v1.0 marketing line. |
| **Closed source — no auditability or community contribution** | MIT-licensed, on-device-only. Already true. Principle 6. |
| **Cross-post deduplication on the timeline** *(Indigo's signature)* | Indigo dedups *cards*; SocialFusion stitches *conversations*. **The Fuse** as architecture, not presentation. |
| **Direct messages — basic** | Full streaming + groups + reactions + typing indicators. Built; kept quiet in v1.0. |

### Beats (with explicit acceptance criteria)

| Gap | SocialFusion response |
|---|---|
| **Thread expansion is slow** | Performance budgets: cached thread <200ms / cold <500ms to first paint on iPhone 13. Streaming replies, per-reply retry on failure, skeleton scaffolding, offline fallback, one-side outage in Fused view continues rendering the other side. |
| **Occasional interaction bugs requiring app restart** | **Zero restart-required bugs** as non-negotiable release gate. ≥99.5% crash-free in TestFlight. ≥90% `TimelineValidationDebugView` pass. Manual checklist run per build. Fuse-detection test corpus of 100+ real cross-posts. Bug-bash week before public website. |

### Beats — where audited

| Gap | SocialFusion response |
|---|---|
| **Blue/purple indicators unusable for colorblind readers** | `PlatformLogoBadge` already renders actual platform logos (shape-coded) with glass material. v1.0 commitment: **audit every place network is signaled**, ensure shape-coded element everywhere, add Settings "High-contrast network indicators" toggle, pass colorblind-simulator screenshot check before TestFlight. |

### Matches (must build)

| Gap | SocialFusion response |
|---|---|
| **No timeline / feed search** | Build for v1.0. Two-layer: client-side filter (<100ms) + server-side query (<500ms). Pinned-timeline scoping. Moved into "New for v1.0" above. |
| **Cross-device timeline position sync** | iCloud KVS — Apple-mediated, no backend we control. v1.0 ships iOS/iPadOS sync; Mac picks it up at v1.1. |
| **No Bluesky Lists support** | Pinnable timelines for both Mastodon Lists and Bluesky Lists/Feeds. Plus account-group pins. v1.0 medium depth. |
| **Mute filters not immediately applied** | Immediate, retroactive filter application — sweep loaded timeline on filter change. Glass-box: see the rule and re-show if you change your mind. |

### Same constraint — structural, neither app solves

| Gap | SocialFusion response |
|---|---|
| **No Threads support** | Meta API doesn't expose timeline reading. Our thesis ("federated networks beyond") leaves the door open. |

---

## v1.0 Acceptance Criteria

These are the non-negotiable conditions for promoting v1.0 from TestFlight to App Store.

### Stability
- Zero known restart-required bugs across the manual test checklist.
- ≥ 99.5% crash-free session rate across the last 7 days of TestFlight.
- ≥ 90% `TimelineValidationDebugView` automated test pass rate.
- Full manual checklist (per `CLAUDE.md`) run per TestFlight build, with documented pass/fail.

### Performance
- Cached thread open → first paint < 200ms on iPhone 13 (target floor device).
- Cold thread open → first paint < 500ms on typical mobile connection.
- Unified conversation view streams replies as fetched (no blocking on slow-side network).
- Timeline search client-side filter < 100ms after typing stops.
- Memory < 150MB for typical timeline session.

### Accessibility
- Every network-signaling UI surface passes a colorblind-simulator screenshot review (deuteranopia, protanopia, tritanopia).
- VoiceOver run-through of every primary surface — timeline, compose, thread, profile, DMs, settings, onboarding.
- Dynamic Type at every step from xSmall to AX5.
- Reduce-motion respected on launch animation, Fused bloom, profile parallax.
- Keyboard navigation works for primary surfaces on iPadOS.

### The Fuse
- Detection test corpus of 100+ real cross-posts — false-positive rate < 1%, false-negative rate < 5%.
- Unified conversation view renders correctly when one network is offline (one-side outage handling).
- Echo reply per-post composer correctness: Send button label always reflects current toggle state.
- Onboarding ask works end-to-end; Settings mirror persists choice.

### Quality polish
- Quote post fallback handles missing parent gracefully.
- Error toasts surface for timeline failures (closes existing TODOs).
- No AttributeGraph cycle warnings in console during the manual checklist.

### Public-launch readiness
- Bug-bash week with external testers before public website / press pitches.
- App Store screenshots updated to reflect the five-headline story.
- Privacy manifest, descriptions, and URL scheme verified (already done per recent commits).

---

## What's not in this spec

This is a vision-and-scope spec. The following live in separate, downstream documents:

- **Implementation plan** — concrete tasks, sequencing, and dependencies for the "New for v1.0" list. Will be produced by the `writing-plans` skill as the next step after this spec is approved.
- **Detailed UI mockups** — Figma / full design spec for each new surface (Fused conversation view, per-post composer, onboarding ask, watch list, merged profile cards, pinnable-timeline pins). Reference brainstorm mockups live in `.superpowers/brainstorm/` (gitignored).
- **Marketing copy and landing page** — `frankramblings.com/socialfusion` updates, App Store description, screenshot copy. Aligned to the five-headline story but written separately.
- **Pricing decision** — whether/when/how to monetize advanced features. Principle 7 sets the hard lines but doesn't pre-decide specifics.
- **v1.1 roadmap** — Mac app, full filter editor, custom themes, echo-aware edit/delete propagation, Threads if Meta opens the API. Acknowledged here as deferred but designed separately.
- **Test plan / QA scripts** — concrete TestFlight checklists, manual scripts, colorblind-simulator screenshots. Derived from the acceptance criteria above.

---

## Source artifacts

- Competitive analysis: `docs/competitive/indigo-analysis.md`
- Indigo screenshots: `docs/competitive/indigo_screenshots/`, indexed in `docs/competitive/indigo-screenshots.html`
- Brainstorming mockups (reference; gitignored): `.superpowers/brainstorm/`
- Architecture references: `CLAUDE.md`, `SocialFusion/Views/Components/PlatformLogoBadge.swift`, `SocialFusion/Views/Components/LaunchAnimationView.swift`
