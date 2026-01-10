import SwiftUI
import UIKit

enum PostSystemActions {
    static func openInBrowser(_ post: Post, openURL: OpenURLAction? = nil) {
        guard let url = URL(string: post.originalURL) else { return }
        if let openURL {
            openURL(url)
        } else {
            UIApplication.shared.open(url)
        }
        lightHaptic()
    }

    static func copyLink(_ post: Post) {
        guard let url = URL(string: post.originalURL) else { return }
        UIPasteboard.general.url = url
        lightHaptic()
    }

    static func presentShareSheet(_ post: Post) {
        guard let url = URL(string: post.originalURL) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.excludedActivityTypes = [.assignToContact, .addToReadingList]
        present(activityVC)
        lightHaptic()
    }

    static func openAuthorProfile(_ post: Post, openURL: OpenURLAction? = nil) {
        guard let url = post.authorProfileURL else { return }
        if let openURL {
            openURL(url)
        } else {
            UIApplication.shared.open(url)
        }
        lightHaptic()
    }

    private static func present(_ controller: UIViewController) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow }),
            let rootVC = window.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        if let popover = controller.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(
                x: topVC.view.bounds.midX,
                y: topVC.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        topVC.present(controller, animated: true, completion: nil)
    }

    private static func lightHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
