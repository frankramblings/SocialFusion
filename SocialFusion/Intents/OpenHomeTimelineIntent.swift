import AppIntents
import Foundation
import UIKit

struct OpenHomeTimelineIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Home Timeline"
    static var description = IntentDescription(
        "Opens SocialFusion to the Home timeline.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "socialfusion://timeline")!)
        return .result()
    }
}
