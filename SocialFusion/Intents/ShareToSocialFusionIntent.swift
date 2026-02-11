import AppIntents
import Foundation
import UIKit

struct ShareToSocialFusionIntent: AppIntent {
    static var title: LocalizedStringResource = "Share to SocialFusion"
    static var description = IntentDescription(
        "Opens the SocialFusion composer with pre-filled text, URL, or both.",
        categoryName: "Sharing"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Text", description: "Text to include in the post")
    var text: String?

    @Parameter(title: "URL", description: "A URL to include in the post")
    var url: URL?

    @Parameter(title: "Title", description: "A title for the shared content")
    var title: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        var queryItems: [String] = []

        if let text = text {
            queryItems.append("text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)")
        }
        if let url = url {
            queryItems.append("url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString)")
        }
        if let title = title {
            queryItems.append("title=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title)")
        }

        let query = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        let deepLink = URL(string: "socialfusion://compose\(query)")!

        await UIApplication.shared.open(deepLink)
        return .result()
    }
}
