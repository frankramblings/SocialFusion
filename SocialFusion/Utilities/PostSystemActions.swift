import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

// MARK: - Custom Activity Item Sources for Media Sharing

/// Custom activity item source that properly exposes media types to iOS share sheet
public class MediaActivityItemSource: NSObject, UIActivityItemSource {
    let mediaURL: URL
    let mediaType: Post.Attachment.AttachmentType
    
    public init(mediaURL: URL, mediaType: Post.Attachment.AttachmentType) {
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        super.init()
    }
    
    public func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // Return placeholder - iOS will use this to determine available activities
        return mediaURL
    }
    
    public func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // Return the actual item to share
        return mediaURL
    }
    
    public func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Return proper UTI so iOS recognizes the media type
        switch mediaType {
        case .image:
            return UTType.image.identifier
        case .animatedGIF:
            return UTType.gif.identifier
        case .video, .gifv:
            return UTType.movie.identifier
        case .audio:
            return UTType.audio.identifier
        }
    }
    
    public func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "Shared Media"
    }
}

/// Custom activity item source for UIImage objects
/// This ensures "Save to Photos" appears in the share sheet
public class ImageActivityItemSource: NSObject, UIActivityItemSource {
    let image: UIImage
    
    public init(image: UIImage) {
        self.image = image
        super.init()
    }
    
    public func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // Return UIImage directly as placeholder
        return image
    }
    
    public func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // For "Save to Photos" (saveToCameraRoll), return the UIImage directly
        // For other activities, also return UIImage
        return image
    }
    
    public func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Return image UTI - this is what enables "Save to Photos"
        return UTType.image.identifier
    }
}
