# Indigo Social App: Competitive Analysis for SocialFusion

## Executive Summary

Indigo is a native Apple-platform social client for Bluesky and Mastodon, developed by Aaron Vegh and Ben McCarthy under their studio **Soapbox Software** and launched on May 12, 2026. It is the team's follow-up to their successful cross-posting app Croissant, expanding from pure cross-posting into a full-featured unified timeline client. Indigo has received broadly positive early coverage from the Apple-enthusiast press, with reviewers praising its design quality and the elegance of its unified timeline concept while flagging it clearly as a v1.0 product with gaps that will need addressing over time.[^1][^2][^3][^4]

For SocialFusion — your open-source, MIT-licensed, 100% SwiftUI unified Mastodon and Bluesky client currently in public beta — Indigo is the most direct and credible competitor to have emerged in this space. Understanding where Indigo excels, where it stumbles, and what differentiates it from SocialFusion is essential to positioning your product effectively.

***

## Background: The Team & Pedigree

### Aaron Vegh
Aaron Vegh is a Canadian indie developer and blogger known for his thoughtful public writing about software development. His launch post acknowledged openly that "the Indigo we're shipping today is going to be the worst version," framing v1.0 as a deliberate, humble starting point. This posture — articulate, community-facing, committed to continuous improvement — is consistent with how Croissant was developed.[^5][^1]

### Ben McCarthy
Ben McCarthy is an Irish-based, non-binary indie developer who built Obscura, the well-regarded iOS camera app that was chosen as Apple Editors' Choice, appeared in Apple Store demos, and was downloaded over 1 million times. McCarthy's design instincts are deeply informed by a graphic design background, and they have built a reputation across the indie Apple community for minimalist, polished interfaces. McCarthy also co-wrote a detailed blog post about the design evolution of Indigo, which — while not publicly fetched here — is cited by Six Colors as worth reading.[^4][^6][^7][^8]

### Soapbox Software & Croissant
Indigo was built on the foundation of Croissant, Soapbox's cross-posting tool that supports Mastodon, Bluesky, and Threads from a single interface. The team's prior work meant they had substantial experience with both the ActivityPub and AT Protocol APIs before writing a single line of Indigo's codebase. This is a meaningful advantage: cross-protocol integration is technically difficult, and the team had already solved many of the thornier API edge cases.[^3][^9]

***

## Product Overview

### Core Concept
Indigo's core premise is identical to SocialFusion's: users shouldn't need two apps to follow two networks. Rather than asking users to choose between Mastodon and Bluesky, Indigo merges both feeds into a single chronological timeline. The key design idea is that the social network underlying a post is a technical detail, not the user's primary concern — they want to read their people, wherever those people happen to post.[^3]

### Platform Support
- **iPhone, iPad, Mac** — one subscription covers all three devices[^10][^1]
- No Android support (Apple-only, like SocialFusion)
- Timeline position syncs across devices[^10]

### Pricing Model
| Tier | Price |
|------|-------|
| Free (read-only browse) | $0 |
| Ultraviolet Monthly | $4.99/month |
| Ultraviolet Annual | $34.99/year |
| Ultraviolet One-Time Purchase | $119.99 |

Prices are noted as regional, adjusted by purchasing power index relative to US pricing. The free tier is read-only — users cannot like, reply, repost, or compose without subscribing. This is a relatively high price point compared to single-network competitors (Ivory is $1.99/month, Tapestry is $1.99/month).[^11][^4][^10]

***

## Feature Set

### Unified Timeline
Indigo's signature feature: posts from both Bluesky and Mastodon appear in a single chronological feed. The goal, per the App Store copy, is that "you forget about the technical underpinnings and just enjoy all the people you follow in one place". Visual indicators — blue outlines for Bluesky profiles, purple for Mastodon profiles — preserve context without fragmenting the reading experience.[^12][^13][^3][^10]

### Cross-Post Deduplication
One of Indigo's technically impressive distinguishing features: when two accounts a user follows post the same content to both networks within a few minutes of each other, Indigo automatically detects the duplication and merges the two posts into a single entry. Users can toggle between each version and take actions on both simultaneously (quote, reply). This is a genuine problem solved elegantly — cross-posters create noise, and this feature reduces it directly.[^2][^14]

### Cross-Posting Composer
Users can post to both networks simultaneously from a single compose screen, including alt-text, without changing views. Indigo shows simultaneous character-limit countdowns for both Bluesky and Mastodon since the services have different limits. The composer is described as "fast and simple" in App Store copy.[^4][^11][^10]

### Notifications
A unified notifications view combines alerts from both services. Mentions, replies, and quotes are highlighted distinctly, while favs and reposts are grouped together to reduce clutter. Reviewers specifically called out the notification tab as "well done and easy to understand".[^1][^11][^10]

### Direct Messages / Private Posts
Indigo supports Bluesky's native direct messages and wraps Mastodon's private post system into a "conversations" interface. This is notable because the two networks have fundamentally different DM models.[^10]

### Custom Feeds & Lists
Users can access all their Bluesky custom feeds and Mastodon lists through the app's "More" menu. However, Six Colors critic Jason Snell specifically called out the absence of **Bluesky Lists** as a v1.0 gap — the broader custom feeds are present but list support is incomplete.[^3][^4]

### Universal Search
Indigo offers search across both Bluesky and Mastodon from a single search interface. However, Snell also flagged that **searching within your timeline** is not yet possible.[^12][^4][^3]

### Content Filters & Controls
- Keyword and user muting[^12]
- NSFW content filtering / hide toggle[^13][^12]
- Reply filtering (control which replies you see)[^3]
- Auto-scroll to new posts[^13]
- Dark mode[^13][^12]

### Thread Detection
The App Store copy describes "an innovative new approach to post detail views that automatically detects threads, making them easier to read all at once". However, Jason Snell reported that "tapping to expose an entire thread can be very slow" in practice — a known v1.0 performance issue.[^4][^10]

### Account Support
Indigo supports multiple accounts of each type (multiple Mastodon instances, multiple Bluesky handles), but **only one account of each network can be active at a time**. Pixel Envy's Nick Heer noted this as "a reasonable compromise" for most users, but a friction point for users who maintain separate personal/professional accounts.[^2]

***

## Design & UI Analysis

### Overall Design Quality
Indigo's design has been consistently praised across all early coverage. Warner Crocker's review specifically highlighted that "it's very well designed, and easy to discover its functionality," and stated that the developers "have done an excellent job" for a first version. Pixel Envy's Nick Heer, who used Indigo as his primary social client before launch, said "everything feels right". The Australian App Store has a user review calling it "Best third party app for Bluesky/Mastodon hands down. Love the UI, design elements and how smooth it is to use".[^15][^1][^2]

Ben McCarthy's graphic design background and decade of iOS app development experience (including an Apple Editors' Choice award for Obscura) are evident in the product's polish. The App Store copy describes the UI as aiming to be "modern" while making "common interactions faster and less disruptive".[^7][^10]

### Color Coding System
The blue (Bluesky) / purple (Mastodon) visual distinction is the primary design mechanism for maintaining network context in a merged feed. It is widely considered elegant and functional. However, Six Colors critic Jason Snell — who disclosed being colorblind — specifically called out that "the app's choice of colors… [is] impossible for me to differentiate as a colorblind person." There is a workaround: users can add a badge to each account's avatar to differentiate them. But Snell wrote "it would sure be nice to pick a better color scheme." This is an accessibility gap in an otherwise accessibility-conscious product.[^12][^4]

### Notification Design
The notification view's design — separating high-signal interactions (mentions, replies, quotes) from lower-signal activity (favs, reposts) — reflects careful UX thinking about information hierarchy. The grouping of lower-priority actions reduces visual clutter while keeping the feed actionable.[^10]

### Native Feel
Indigo is a native Apple app (not cross-platform framework), which means it benefits from full platform fit: smooth scrolling, pull-to-refresh, proper dark mode implementation, and familiar iOS interaction patterns. This distinguishes it from cross-platform competitors like Openvibe.[^10]

***

## What Reviewers Are Saying

### Jason Snell — Six Colors (May 13, 2026)
The most substantive early review available, from one of Apple's most trusted long-form technology critics. Snell used Indigo for approximately one month before launch as his **primary social-media client**, having "largely stopped using individual clients dedicated to the two services" as a result. Key quotes and observations:[^4]

- "Indigo excels at scrolling through a timeline."[^4]
- "Get too far beyond that, though, and you'll find that it's still definitely a 1.0 product."[^4]
- Specific gaps cited: no timeline search, slow thread expansion, no Bluesky list support, mute filters not applied immediately to all timeline items[^4]
- Accessibility gap: blue/purple color scheme unusable for colorblind users[^4]
- Occasional interaction bugs requiring quit-and-relaunch[^4]
- "While I prefer Indigo because I want to scroll a timeline once and only once, it's not yet at the level of a dedicated app like Tapbots's Ivory for Mastodon."[^4]

### Warner Crocker — Life on the Wicked Stage (May 13, 2026)
A positive review from a theatre director and technology blogger who covers Apple software with a strong focus on design quality. Crocker praised the execution and noted the team's track record with Croissant as a confidence signal. He was candid that the unified timeline isn't his personal priority, but recommended it strongly for users who want it.[^1]

### Nick Heer — Pixel Envy (May 11, 2026)
Heer, a respected Apple blogger, endorsed Indigo enthusiastically as his primary Bluesky and Mastodon client, calling the mixing of services "better than I had imagined". His review also surfaced the account-switching limitation: only one active account per network at a time.[^2]

### TechCrunch (May 12, 2026)
Coverage framed Indigo in the context of the broader "leaving billionaire-owned social media" trend, presenting it as an onramp to the open social web. The TechCrunch piece is notable for being the primary publication McCarthy spoke to directly about the app's origins.[^3]

### Six Colors Summary (Jason Snell)
"Meanwhile, Aaron Vegh and Ben McCarthy released Indigo, an app that unifies your Mastodon and Bluesky timelines, thus reducing the amount of madness in your life."[^16]

***

## Known Gaps & v1.0 Limitations

The following limitations are confirmed by reviewer observations and/or App Store user feedback:

| Gap | Source |
|-----|--------|
| No timeline/feed search | Six Colors[^4] |
| Thread expansion is slow | Six Colors[^4] |
| No Bluesky Lists support | Six Colors[^4] |
| Mute filters not immediately applied to all timeline items | Six Colors[^4] |
| Occasional interaction bugs requiring app restart | Six Colors[^4] |
| Blue/purple color distinction inaccessible to colorblind users | Six Colors[^4] |
| Only one active account per network (no simultaneous multi-account) | Pixel Envy[^2] |
| No Threads support (read or post) | Warner Crocker[^1] |
| No Android support | App Store[^10] |
| Limited icon customization | App Store user review[^15] |
| One-time purchase may not include all future features | App Store disclaimer[^10][^11] |

The Threads omission is structurally interesting: Croissant (Soapbox's earlier app) does support Threads cross-posting, but Indigo excludes it. Crocker notes this is because Threads "doesn't allow for viewing its timelines in the same way" — the Threads API does not currently expose timeline reading in a way that would support Indigo's model.[^1]

***

## Social & Community Reception

### Fediverse & Bluesky
The launch generated solid organic engagement among the Apple / open-web community. The Product Hunt launch received 90+ upvotes within the first few days. The App Store rating in the Brazilian store shows 4.8 out of 5 across 68 ratings; the Australian store shows 4.4 out of 5 across 7 ratings with a user calling it "Best third party app for Bluesky/Mastodon hands down". The wider fediverse reaction has been positive, particularly among users who were already using Croissant and were primed to trust the team.[^17][^18][^15]

### Coverage Spread
Indigo was picked up by TechCrunch, Six Colors, Pixel Envy, Global Dating Insights, mezha.net, fenado.ai, NewsBytes, and Tip Ranks, among others — a strong showing for an indie app in the Apple space. The TechCrunch article in particular provides mainstream legitimacy.[^9][^19][^20][^2][^13][^12][^3][^4]

### Developer Transparency
Aaron Vegh's public blog framing ("this is the worst version") created goodwill in the community by setting honest expectations rather than over-promising. This is consistent with how thoughtful indie Apple developers communicate and builds long-term trust.[^5][^1]

***

## Competitive Landscape: Multi-Network Social Clients

Indigo enters a category with several existing players, each with distinct positioning:

| App | Networks | Posting | iOS Native | Open Source | Price |
|-----|----------|---------|------------|-------------|-------|
| **Indigo** | Mastodon, Bluesky | ✅ Cross-post | ✅ | ❌ | $4.99/mo or $35/yr |
| **SocialFusion** | Mastodon, Bluesky | ✅ Cross-post | ✅ SwiftUI | ✅ MIT | Free (beta) |
| **Openvibe** | Mastodon, Bluesky, Nostr, Threads | ✅ Cross-post | ❌ (cross-platform) | ❌ | Free[^21][^22] |
| **Tapestry** | Bluesky, Mastodon, RSS, YouTube, Tumblr, Podcasts | ❌ Read-only | ✅ | ❌ | $1.99/mo[^23][^24] |
| **Croissant** | Mastodon, Bluesky, Threads | ✅ Post-only, no timeline | ✅ | ❌ | Unknown |
| **Ivory** | Mastodon only | ✅ | ✅ | ❌ | $1.99/mo[^25][^26] |
| **Ice Cubes** | Mastodon only | ✅ | ✅ SwiftUI | ✅ AGPL | Free[^27] |

### Key Competitive Observations

**Openvibe** supports more networks (adding Nostr and Threads) but is cross-platform and has been criticized for producing an unmanageable "firehose" unless users follow small numbers of accounts across services. Its UX is not considered native-quality by Apple users.[^28]

**Tapestry** (from the Twitterrific/Iconfactory team) has broader feed support (RSS, YouTube, podcasts) but is explicitly read-only — it does not support social posting at all. It's a consumption tool, not a social client.[^29][^24]

**Ivory** remains the gold standard for Mastodon-only iOS clients and is frequently cited as the benchmark Indigo should aspire to match over time. It represents mature, polished single-network execution.[^4]

**SocialFusion** is the most structurally similar product to Indigo: iOS-native, SwiftUI, Mastodon + Bluesky only, with unified timeline and cross-posting. The key differentiators are open-source licensing, current free pricing in beta, and the development philosophy.

***

## SocialFusion vs. Indigo: Direct Comparison

### Where Indigo Has Advantages
1. **Shipping product with paying users**: Indigo has launched publicly on the App Store; SocialFusion is in public beta[^30][^3]
2. **Team pedigree and press credibility**: Ben McCarthy's Obscura background and Soapbox's Croissant track record have generated significant organic press trust[^6][^7][^3]
3. **Mac app included**: A proper macOS client ships on day one alongside iPhone and iPad[^3][^10]
4. **Duplicate post detection**: Indigo's cross-post deduplication is a technically sophisticated feature that SocialFusion's current public feature set doesn't describe matching[^2][^10]
5. **Bluesky DM support**: Native DM integration is present in Indigo[^10]
6. **Device sync**: Timeline position syncs across iPhone, iPad, and Mac[^10]

### Where SocialFusion Has Advantages
1. **Open source (MIT license)**: SocialFusion's full source is public and auditable. Indigo is closed-source. This is a meaningful philosophical differentiator in the open social web community.[^30]
2. **Free access to full functionality**: SocialFusion's current beta is free, while Indigo gates all interaction behind a $4.99/month paywall[^30][^4]
3. **No server, no passwords**: SocialFusion stores credentials locally in the iOS Keychain with no backend server — a trust and privacy argument that resonates with the open-web ethos[^30]
4. **SwiftUI native**: SocialFusion's 100% SwiftUI architecture is a platform-fit and accessibility story[^30]
5. **Community contribution**: An open-source app can receive community bug reports, pull requests, and feedback in ways a closed app cannot[^30]
6. **No paywalled reading limit**: Indigo's free tier is read-only — even liking a post requires a subscription[^11][^4]

### Where Both Apps Share v1.0 Growing Pains
Both are early-stage products in a technically complex space. Indigo's known gaps (slow threads, limited search, colorblind accessibility) are the kind of issues SocialFusion should proactively avoid or address to distinguish itself. Indigo's public acknowledgment of being a "worst version" is also an opportunity: users who want a polished, feature-complete client today may not get it from either app, but SocialFusion can position its openness and community-building as the differentiating journey rather than a weakness.

***

## Strategic Implications for SocialFusion

### Positioning Opportunities

**1. Open Source as Trust Anchor**
The open social web community is deeply attuned to transparency and user trust. SocialFusion's MIT license and "no server" architecture are not just technical choices — they are values statements. Indigo does not offer this. Lean into this distinction explicitly in your marketing copy and README.

**2. Free Full Access vs. Paywalled Interaction**
Indigo's paywall on even basic post interaction ($4.99/month) will generate friction for casual users and enthusiasts on limited budgets. SocialFusion's free full beta is an obvious acquisition advantage. When SocialFusion eventually monetizes, consider whether your model can remain more accessible (one-time purchase, lower monthly tier, or truly unlimited free tier).

**3. Accessibility**
Six Colors' colorblind accessibility critique of Indigo is a concrete, addressable gap. SocialFusion already cites VoiceOver, Dynamic Type, and WCAG compliance as first-class features. This is a real differentiator if executed well. Adding user-configurable network indicator colors or a pattern/shape-based distinction (in addition to color) would directly address Indigo's reported weakness.[^30]

**4. Feature Parity Targets**
Given Indigo's v1.0 gaps, SocialFusion should prioritize shipping these features to differentiate:
- **Fast thread expansion** (Indigo's is slow per Six Colors)
- **Timeline/feed search** (absent in Indigo)
- **Immediate mute filter application** (delayed in Indigo)
- **Colorblind-accessible network indicators**
- **Robust multi-account support** (Indigo limits one active account per network)

**5. The Threads Question**
Neither Indigo nor SocialFusion currently integrates Threads. Openvibe does. If Meta opens its API sufficiently, this could be a differentiating addition that expands SocialFusion's audience well beyond the current Mastodon/Bluesky power-user niche.

**6. Leaning Into SwiftUI**
SocialFusion's 100% SwiftUI architecture is a story worth telling explicitly to the iOS developer community — there's genuine interest in how a SwiftUI-native cross-protocol social client is built. This can generate developer goodwill, contributions, and coverage in the Apple developer press (MacStories, Six Colors, etc.).

### Competitive Risks

- **Soapbox's pace of iteration**: If Aaron Vegh and Ben McCarthy close Indigo's known gaps quickly (thread speed, search, colorblind accessibility), the competitive window narrows. Monitor their update cadence.
- **Indigo's press network**: Coverage from TechCrunch and Six Colors at launch gives Indigo strong organic discovery momentum. SocialFusion will need to earn coverage proactively.
- **Price as a long-term strategy**: SocialFusion's current free beta can't last forever. How and when you monetize will be a defining product decision that must balance sustainability with community trust.

***

## Summary Assessment

Indigo is a well-designed, thoughtfully conceived v1.0 from a credible, experienced indie development team. It will improve quickly. For SocialFusion, Indigo's existence validates the product category and raises the visibility of the unified-timeline concept — which is good. At the same time, Indigo's closed source, paywalled interaction, and concrete v1.0 gaps (accessibility, thread performance, timeline search) represent real, addressable differentiators for SocialFusion to claim.

The ideal SocialFusion positioning is not "Indigo, but cheaper" — it's "the open social web's own open-source client": community-built, community-audited, free to use, and designed with accessibility as a core value rather than an afterthought.

---

## References

1. [Indigo: A Well Designed Social Media App For Those Who Need It](https://warnercrocker.com/2026/05/13/indigo-a-well-designed-social-media-app-for-those-who-need-it/) - ” For the worst and first version, I believe Aaron and Ben McCarthy have done an excellent job. (You...

2. [Aaron Vegh and Ben McCarthy Launch Indigo - Pixel Envy](https://pxlnv.com/linklog/soapbox-indigo/) - Go get it on the App Store! I have been using Indigo for a while as my primary iOS client for Bluesk...

3. [Indigo brings the open social web to one app - TechCrunch](https://techcrunch.com/2026/05/12/indigo-brings-the-open-social-web-to-one-app/) - Indigo's new social app lets you cross-post to the open social web, including Mastodon and Bluesky, ...

4. [Indigo unifies the Mastodon and Bluesky timelines - Six Colors](https://sixcolors.com/post/2026/05/indigo-unifies-the-mastodon-and-bluesky-timelines/) - Indigo, from Soapbox Software, is a new social media client that combines Bluesky and Mastodon timel...

5. [Home - Life on the Wicked Stage: Act 3](https://warnercrocker.com/home/) - It's a first version of the app, and as one of the developers, Aaron Vegh says on his blog, “The Ind...

6. [How Ben McCarthy is bringing Obscura's vision to photo editing](https://www.sketch.com/blog/obscura-studio/) - Discover how Obscura Studio strips photo editing down to its essentials. We spoke with creator Ben M...

7. [Issue 5 - Obscura - IndieAppSpotlight](https://indieappspotlight.com/p/issue-5-obscura) - This week, we're exploring Obscura, a brilliant photography application created by Ben McCarthy.

8. [Issue #37: Obscura by Ben McCarthy - Indie Watch](https://indie.watch/issue-37-obscura-by-ben-mccarthy/) - Today, we're looking at Obscura by Ben McCarthy. Obscura is an advanced camera app that offers an im...

9. [Indigo Unifies Decentralized Social Networks with Single App ...](https://fenado.ai/articles/indigo-unifies-decentralized-social-networks-with-single-app-offering-cross-posting-and-unified-feeds) - Developed by Soapbox Software, the app allows individuals to explore and interact with decentralized...

10. [Indigo for Bluesky & Mastodon - App Store - Apple](https://apps.apple.com/gb/app/indigo-for-bluesky-mastodon/id6763755310) - Download Indigo for Bluesky & Mastodon by Soapbox Software Inc on the App Store. See screenshots, ra...

11. [Indigo for Bluesky & Mastodon - App Store - Apple](https://apps.apple.com/us/app/indigo-for-bluesky-mastodon/id6763755310) - Download Indigo for Bluesky & Mastodon by Soapbox Software Inc on the App Store. See screenshots, ra...

12. [Indigo App Unifies Mastodon and Bluesky in Single Interface](https://www.globaldatinginsights.com/featured/indigo-app-unifies-mastodon-and-bluesky-in-single-interface/?amp) - Rather than forcing users to choose between Mastodon and Bluesky, the app serves as a single client ...

13. [Indigo launches app to unify Mastodon and Bluesky feeds](https://mezha.net/eng/bukvy/674b3358_indigo_launches_app/) - Indigo launches a unified app to explore Mastodon, Bluesky and Threads from a single synced feed, of...

14. [Aaron Vegh and Ben McCarthy Launch Indigo - Bubbles](https://bubbles.town/entry/4282732) - Go get it on the App Store! I have been using Indigo for a while as my primary iOS client for Bluesk...

15. [Indigo for Bluesky & Mastodon - App Store](https://apps.apple.com/au/app/indigo-for-bluesky-mastodon/id6763755310) - Indigo is a brand new app that combines Bluesky and Mastodon into a single, unified timeline. It can...

16. [Apple, technology, and other stuff - Six Colors](https://sixcolors.com/?member-feed=xxxx&category=Link) - Ben Rice McCarthy has a nice blog post about how the project came to be, and another about how its d...

17. [Indigo — Stay in touch with your people on Bluesky and Mastodon](http://launly.com/products/indigo-2) - Indigo is a brand new app that combines Bluesky and Mastodon into a single, unified timeline. It can...

18. [Indigo for Bluesky & Mastodon - App Store - Apple](https://apps.apple.com/us/app/indigo-for-bluesky-mastodon/id6763755310?l=pt-BR) - Indigo is a brand new app that combines Bluesky and Mastodon into a single, unified timeline. It can...

19. [Indigo Launches Unified App for Decentralized Social Media Power ...](https://www.tipranks.com/news/private-companies/indigo-launches-unified-app-for-decentralized-social-media-power-users) - Indigo, a new app from Soapbox Software, has launched as a unified interface for decentralized socia...

20. [Indigo launches May 12, 2026 unifying Mastodon and Bluesky timelines](https://www.newsbytesapp.com/news/science/indigo-launches-may-12-2026-unifying-mastodon-and-bluesky-timelines/tldr) - Indigo, a new app by Soapbox Software, unifies decentralized networks Mastodon and Bluesky into one ...

21. [Openvibe combines Mastodon, Bluesky and Nostr into one social app](https://techcrunch.com/2024/07/09/openvibe-combines-mastodon-bluesky-and-nostr-into-one-social-app/) - Ahead of these potential competitors comes Openvibe, a simple aggregator for the open social web.

22. [Openvibe – Open Social App](https://apps.apple.com/nz/app/openvibe-open-social-app/id1666230916) - Openvibe: Your Gateway to Open Social Networking Mastodon, Bluesky, Nostr & Threads in a single app!...

23. [Twitterrific team launches new 'Tapestry' iPhone app for Bluesky ...](https://9to5mac.com/2025/02/04/twitterrific-team-launches-new-iphone-app-tapestry-for-bluesky-mastodon-more/) - The makers of Twitterrific just launched a new iPhone app for social and web feeds. Tapestry brings ...

24. [The new Tapestry app unifies social feeds into a single timeline](https://www.idownloadblog.com/2025/02/04/tapestry-app-social-feeds-bluesky-mastodon-youtube-rss/) - Tapestry for iPhone and iPad pulls together social feeds from Bluesky, Mastodon, YouTube, RSS and ot...

25. [Tweetbot Developer Launches Ivory, Its New Mastodon App For The iPhone And iPad - BGR](https://www.bgr.com/tech/tweetbot-developer-launches-ivory-its-new-mastodon-app-for-the-iphone-and-ipad/) - Tapbots, the developer behind Tweetbot, has officially launched Ivory, its new iOS and iPadOS app fo...

26. [Ivory for Mastodon Review: Tapbots Reborn - MacStories](https://www.macstories.net/reviews/ivory-for-mastodon-review-tapbots-reborn/) - There's an intangible, permeating quality about Tapbots apps that transcends features and specs: cra...

27. [Dimillian/IceCubesApp: A SwiftUI Mastodon client](https://github.com/Dimillian/IceCubesApp) - A SwiftUI Mastodon client. Contribute to Dimillian/IceCubesApp development by creating an account on...

28. [OpenVibe (Mastodon/Bluesky/Nostr/Threads/RSS App)](https://hyperborea.org/reviews/apps/openvibe/) - A cool idea, and it looks great, but the combined feed is too much of a firehose unless you're only ...

29. [Twitterrific Developers Launch Tapestry, a "Universal Timeline" App](https://www.thurrott.com/cloud/316756/twiterrific-developers-launch-tapestry-a-universal-timeline-app) - Tapestry, the new app from Twitterrific developer The Iconfactory offers a unified timeline that agg...

30. [SocialFusion — Your Unified Social Timeline - frank ramblings](https://frankramblings.com/socialfusion/) - SocialFusion brings your Mastodon and Bluesky timelines together in one beautiful iOS app. Open sour...

