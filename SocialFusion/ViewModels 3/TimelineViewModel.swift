// Pre-load parent posts for instant expand (Mastodon + Bluesky)
for post in self.posts {
    if let parentID = post.inReplyToID ?? post.inReplyToBlueskyID {
        service.fetchPost(id: parentID) { parent in
            guard let parent = parent else { return }
            if let idx = self.posts.firstIndex(where: { $0.id == post.id }) {
                self.posts[idx].parent = parent
            }
        }
    }
}
