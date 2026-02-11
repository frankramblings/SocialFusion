import AppIntents
import Foundation
import UIKit

struct CreateDraftIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Draft in SocialFusion"
    static var description = IntentDescription(
        "Creates a draft post in SocialFusion. Optionally opens the editor.",
        categoryName: "Sharing"
    )
    static var openAppWhenRun = true

    @Parameter(title: "Text", description: "Text for the draft post")
    var text: String?

    @Parameter(title: "URL", description: "A URL to include in the draft")
    var url: URL?

    @Parameter(title: "Open Editor", description: "Whether to open the editor after creating the draft", default: true)
    var openEditor: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        var queryItems: [String] = []

        if let text = text {
            queryItems.append("text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)")
        }
        if let url = url {
            queryItems.append("url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString)")
        }
        queryItems.append("open=\(openEditor ? "true" : "false")")

        let query = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        let deepLink = URL(string: "socialfusion://draft\(query)")!

        await UIApplication.shared.open(deepLink)
        return .result()
    }
}
