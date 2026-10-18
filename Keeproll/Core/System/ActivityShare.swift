import UIKit

/// Presents the system share sheet from the top-most view controller.
///
/// SwiftUI's `ShareLink` inside a sheet can dismiss that sheet too after an action such
/// as "Save Image", so Summary closed without running Done (QA L5). Presenting the
/// activity controller directly only ever dismisses itself.
@MainActor
enum ActivityShare {
    static func present(_ items: [Any], completion: (() -> Void)? = nil) {
        guard let top = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, error in
            Log.ui.debug("Share sheet closed: \(activity?.rawValue ?? "none", privacy: .public), completed \(completed), error \(error != nil)")
            completion?()
        }
        // iPad needs an anchor; centre it on the presenting view.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
