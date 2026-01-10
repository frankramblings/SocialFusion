import SwiftUI
import UIKit

struct ShareSheetWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?
    let sourceView: UIView?
    let sourceRect: CGRect?

    init(
        activityItems: [Any],
        excludedActivityTypes: [UIActivity.ActivityType]? = nil,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil
    ) {
        self.activityItems = activityItems
        self.excludedActivityTypes = excludedActivityTypes
        self.sourceView = sourceView
        self.sourceRect = sourceRect
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes

        if let popover = controller.popoverPresentationController {
            popover.sourceView = sourceView ?? controller.view
            popover.sourceRect = sourceRect
                ?? CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
