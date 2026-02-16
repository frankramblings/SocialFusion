import AppIntents
import Foundation
import UIKit

struct OpenNotificationsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Notifications"
    static var description = IntentDescription(
        "Opens SocialFusion to the Notifications tab.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await UIApplication.shared.open(URL(string: "socialfusion://notifications")!)
        return .result(dialog: "Opened Notifications")
    }
}
