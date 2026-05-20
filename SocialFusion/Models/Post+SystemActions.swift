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

    /// Reports the post via the service manager with consistent feedback.
    /// Centralizes haptic + toast feedback for the five UI sites that
    /// otherwise fire-and-forget the report Task. Without this wrapper,
    /// users got no visible confirmation that the report went through,
    /// which is exactly the wrong feel for a serious moderation action.
    func report(via serviceManager: SocialServiceManager, reason: String? = nil) {
        Task {
            do {
                try await serviceManager.reportPost(self, reason: reason)
                await MainActor.run {
                    HapticEngine.success.trigger()
                    ToastManager.shared.show("Report sent", severity: .success, duration: 1.6)
                }
            } catch {
                await MainActor.run {
                    HapticEngine.error.trigger()
                    ToastManager.shared.show("Couldn't send report", severity: .error, duration: 2.0)
                }
                ErrorHandler.shared.handleError(error)
            }
        }
    }
}
