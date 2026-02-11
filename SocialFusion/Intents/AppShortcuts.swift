import AppIntents

struct SocialFusionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenInSocialFusionIntent(),
            phrases: [
                "Open link in \(.applicationName)",
                "View link in \(.applicationName)"
            ],
            shortTitle: "Open URL",
            systemImageName: "link"
        )

        AppShortcut(
            intent: ShareToSocialFusionIntent(),
            phrases: [
                "Share to \(.applicationName)",
                "Post to \(.applicationName)"
            ],
            shortTitle: "Share",
            systemImageName: "square.and.arrow.up"
        )

        AppShortcut(
            intent: OpenHomeTimelineIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my timeline in \(.applicationName)",
                "Open \(.applicationName) timeline"
            ],
            shortTitle: "Home Timeline",
            systemImageName: "house"
        )

        AppShortcut(
            intent: OpenNotificationsIntent(),
            phrases: [
                "Show \(.applicationName) notifications",
                "Open \(.applicationName) notifications"
            ],
            shortTitle: "Notifications",
            systemImageName: "bell"
        )

        AppShortcut(
            intent: PostWithConfirmationIntent(),
            phrases: [
                "Compose a post in \(.applicationName)",
                "Write a post in \(.applicationName)"
            ],
            shortTitle: "Compose Post",
            systemImageName: "square.and.pencil"
        )
    }
}
