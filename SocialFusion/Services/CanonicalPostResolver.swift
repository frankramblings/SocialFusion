import Foundation

struct CanonicalPostIdentity: Equatable {
  let canonicalPostID: String
  let nativeKeys: Set<NativePostKey>
  let originNetwork: SocialPlatform
}

struct CanonicalPostResolution: Equatable {
  let canonicalPostID: String
  let nativeKeys: Set<NativePostKey>
  let canonicalPost: CanonicalPost
  let socialEvents: [SocialEvent]
}

enum CanonicalPostResolver {
  static func resolve(post: Post, sourceAccountID: String? = nil) -> CanonicalPostResolution {
    let canonicalSource = post.originalPost ?? post
    let (primaryKey, nativeKeys) = nativeKeys(for: canonicalSource)
    let canonicalPostID = canonicalID(for: primaryKey)

    var canonicalPost = CanonicalPost(
      id: canonicalPostID,
      originNetwork: canonicalSource.platform,
      nativeKeys: nativeKeys,
      createdAt: canonicalSource.createdAt,
      lastSocialActivityAt: canonicalSource.createdAt,
      post: canonicalSource,
      socialContext: SocialContext()
    )

    let socialEvents = socialEventsFromBoost(
      post: post,
      canonicalPostID: canonicalPostID,
      sourceAccountID: sourceAccountID
    )

    if let latestEvent = socialEvents.map({ $0.occurredAt }).max() {
      canonicalPost.lastSocialActivityAt = max(canonicalPost.createdAt, latestEvent)
    }

    return CanonicalPostResolution(
      canonicalPostID: canonicalPostID,
      nativeKeys: nativeKeys,
      canonicalPost: canonicalPost,
      socialEvents: socialEvents
    )
  }

  static func resolve(mastodonStatus: MastodonStatus, account: SocialAccount) -> CanonicalPostIdentity {
    let originalID = mastodonStatus.reblog?.id ?? mastodonStatus.id
    let originalURL = mastodonStatus.reblog?.url ?? mastodonStatus.url
    let host = hostFrom(urlString: originalURL) ?? hostFrom(urlString: account.serverURL?.absoluteString)
    let keyValue = host != nil ? "activitypub:\(host!):\(originalID)" : "activitypub:\(originalID)"
    let primaryKey = NativePostKey(network: .mastodon, key: keyValue)

    var nativeKeys: Set<NativePostKey> = [primaryKey]
    if let url = originalURL {
      nativeKeys.insert(NativePostKey(network: .mastodon, key: "activitypub:url:\(url)"))
    }

    return CanonicalPostIdentity(
      canonicalPostID: canonicalID(for: primaryKey),
      nativeKeys: nativeKeys,
      originNetwork: .mastodon
    )
  }

  static func resolve(blueskyItem: BlueskyFeedItem) -> CanonicalPostIdentity {
    let primaryKey = NativePostKey(network: .bluesky, key: "atproto:\(blueskyItem.post.uri)")
    var nativeKeys: Set<NativePostKey> = [primaryKey]
    nativeKeys.insert(NativePostKey(network: .bluesky, key: "atproto:cid:\(blueskyItem.post.cid)"))

    return CanonicalPostIdentity(
      canonicalPostID: canonicalID(for: primaryKey),
      nativeKeys: nativeKeys,
      originNetwork: .bluesky
    )
  }

  private static func socialEventsFromBoost(
    post: Post,
    canonicalPostID: String,
    sourceAccountID: String?
  ) -> [SocialEvent] {
    guard post.originalPost != nil else { return [] }

    let actorID = post.authorId.isEmpty ? post.authorUsername : post.authorId
    let actorHandle = post.authorUsername
    let displayName = post.authorName.isEmpty ? post.authorUsername : post.authorName
    let actor = SocialActor(
      id: actorID,
      handle: actorHandle,
      displayName: displayName,
      platform: post.platform,
      accountID: sourceAccountID
    )

    let nativeEventKey = !post.platformSpecificId.isEmpty ? post.platformSpecificId : post.id
    let eventKeyPart = nativeEventKey.isEmpty ? ISO8601DateFormatter().string(from: post.createdAt) : nativeEventKey
    let eventID = "\(post.platform.rawValue):repost:\(actorID):\(canonicalPostID):\(eventKeyPart)"

    return [
      SocialEvent(
        id: eventID,
        type: .repost,
        canonicalPostID: canonicalPostID,
        actor: actor,
        occurredAt: post.createdAt,
        nativeEventKey: nativeEventKey.isEmpty ? nil : nativeEventKey
      )
    ]
  }

  private static func nativeKeys(for post: Post) -> (NativePostKey, Set<NativePostKey>) {
    switch post.platform {
    case .mastodon:
      let host = hostFrom(urlString: post.originalURL)
      let idValue = post.platformSpecificId.isEmpty ? post.id : post.platformSpecificId
      let keyValue = host != nil ? "activitypub:\(host!):\(idValue)" : "activitypub:\(idValue)"
      let primaryKey = NativePostKey(network: .mastodon, key: keyValue)
      var keys: Set<NativePostKey> = [primaryKey]
      if !post.originalURL.isEmpty {
        keys.insert(NativePostKey(network: .mastodon, key: "activitypub:url:\(post.originalURL)"))
      }
      return (primaryKey, keys)
    case .bluesky:
      let uri = post.platformSpecificId.isEmpty ? post.id : post.platformSpecificId
      let primaryKey = NativePostKey(network: .bluesky, key: "atproto:\(uri)")
      var keys: Set<NativePostKey> = [primaryKey]
      if let cid = post.cid, !cid.isEmpty {
        keys.insert(NativePostKey(network: .bluesky, key: "atproto:cid:\(cid)"))
      }
      return (primaryKey, keys)
    }
  }

  private static func canonicalID(for primaryKey: NativePostKey) -> String {
    "canonical:\(primaryKey.storageKey)"
  }

  private static func hostFrom(urlString: String?) -> String? {
    guard let urlString = urlString, let url = URL(string: urlString) else { return nil }
    return url.host
  }
}
