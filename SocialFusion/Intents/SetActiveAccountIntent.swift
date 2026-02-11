import AppIntents
import Foundation
import UIKit

struct SetActiveAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Active Account"
    static var description = IntentDescription(
        "Switches the active account in SocialFusion.",
        categoryName: "Account"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Account")
    var account: SocialAccountEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let encoded = account.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account.id
        let deepLink = URL(string: "socialfusion://account/\(encoded)")!

        await UIApplication.shared.open(deepLink)
        return .result()
    }
}
