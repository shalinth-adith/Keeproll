import Observation
import Foundation

enum Route: Hashable {
    case similar, screenshots, blurry, videos, contacts, calendar, vault, swipe, calibration
    case compare(groupID: UUID, startID: String)
}

enum Sheet: Identifiable {
    case review
    case videoPreview(id: String)
    case compress(MediaItem)

    var id: String {
        switch self {
        case .review: "review"
        case .videoPreview(let id): "video:\(id)"
        case .compress(let item): "compress:\(item.id)"
        }
    }
}

@Observable
final class AppRouter {
    var path: [Route] = []
    var sheet: Sheet?

    /// Compare and Swipe carry their own bottom controls, so the global bar steps aside.
    var hidesSelectionBar: Bool {
        switch path.last {
        case .compare, .swipe, .calibration: true
        default: false
        }
    }

    func open(_ route: Route) { path.append(route) }
    func presentReview() { sheet = .review }
    func previewVideo(_ id: String) { sheet = .videoPreview(id: id) }

    /// After cleaning, go back to the dashboard.
    func finishCleanup() {
        sheet = nil
        path.removeAll()
    }
}
