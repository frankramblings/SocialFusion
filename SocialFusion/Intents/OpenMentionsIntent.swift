import AppIntents
import Foundation
import UIKit

struct OpenMentionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Mentions"
    static var description = IntentDescription(
        "Opens SocialFusion to the Mentions view.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await UIApplication.shared.open(URL(string: "socialfusion://mentions")!)
        return .result(dialog: "Opened Mentions")
    }
}
