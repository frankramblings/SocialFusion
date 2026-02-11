import AppIntents
import Foundation
import UIKit

struct PostWithConfirmationIntent: AppIntent {
    static var title: LocalizedStringResource = "Post with SocialFusion"
    static var description = IntentDescription(
        "Opens the SocialFusion composer so you can review and post. You must tap Post to publish.",
        categoryName: "Sharing"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Text", description: "Text to include in the post")
    var text: String?

    @Parameter(title: "URL", description: "A URL to include in the post")
    var url: URL?

    @MainActor
    func perform() async throws -> some IntentResult {
        var queryItems: [String] = []

        if let text = text {
            queryItems.append("text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)")
        }
        if let url = url {
            queryItems.append("url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString)")
        }

        let query = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        let deepLink = URL(string: "socialfusion://compose\(query)")!

        await UIApplication.shared.open(deepLink)
        return .result()
    }
}
