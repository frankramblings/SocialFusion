import SwiftUI

extension Post {
    var authorProfileURL: URL? {
        switch platform {
        case .mastodon:
            guard let original = URL(string: originalURL) else { return nil }
            let components = original.path.split(separator: "/")
            guard let handle = components.first else { return nil }
            let profilePath = "/\(handle)"
            return URL(string: profilePath, relativeTo: original)?.absoluteURL
        case .bluesky:
            let handle = authorUsername.isEmpty ? nil : authorUsername
            guard let handle else { return nil }
            return URL(string: "https://bsky.app/profile/\(handle)")
        }
    }

    func openInBrowser(openURL: OpenURLAction? = nil) {
        PostSystemActions.openInBrowser(self, openURL: openURL)
    }

    func copyLink() {
        PostSystemActions.copyLink(self)
    }

    func presentShareSheet() {
        PostSystemActions.presentShareSheet(self)
    }

    func openAuthorProfile(openURL: OpenURLAction? = nil) {
        PostSystemActions.openAuthorProfile(self, openURL: openURL)
    }
}
