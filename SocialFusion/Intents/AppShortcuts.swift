import AppIntents

struct SocialFusionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PostWithConfirmationIntent(),
            phrases: [
                "Compose a post in \(.applicationName)",
                "Write a post in \(.applicationName)",
                "New post in \(.applicationName)",
                "Post to \(.applicationName)",
            ],
            shortTitle: "Compose Post",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: CreateDraftIntent(),
            phrases: [
                "Save a draft in \(.applicationName)",
                "Draft a post in \(.applicationName)",
                "New draft in \(.applicationName)",
            ],
            shortTitle: "Save Draft",
            systemImageName: "doc.text"
        )

        AppShortcut(
            intent: OpenHomeTimelineIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my timeline in \(.applicationName)",
                "Open \(.applicationName) timeline",
                "What's new in \(.applicationName)",
            ],
            shortTitle: "Home Timeline",
            systemImageName: "house"
        )

        AppShortcut(
            intent: OpenNotificationsIntent(),
            phrases: [
                "Show \(.applicationName) notifications",
                "Open \(.applicationName) notifications",
                "Check \(.applicationName) notifications",
            ],
            shortTitle: "Notifications",
            systemImageName: "bell"
        )

        AppShortcut(
            intent: OpenMentionsIntent(),
            phrases: [
                "Show my \(.applicationName) mentions",
                "Open \(.applicationName) mentions",
                "Who mentioned me in \(.applicationName)",
            ],
            shortTitle: "Mentions",
            systemImageName: "at"
        )

        AppShortcut(
            intent: ShareToSocialFusionIntent(),
            phrases: [
                "Share to \(.applicationName)",
                "Send to \(.applicationName)",
            ],
            shortTitle: "Share",
            systemImageName: "square.and.arrow.up"
        )

        AppShortcut(
            intent: OpenInSocialFusionIntent(),
            phrases: [
                "Open link in \(.applicationName)",
                "View link in \(.applicationName)",
            ],
            shortTitle: "Open URL",
            systemImageName: "link"
        )
    }
}
