import Observation
import Foundation

enum Route: Hashable {
    case similar, screenshots, blurry, videos, contacts, swipe
    case compare(groupID: UUID, startID: String)
}

enum Sheet: Identifiable {
    case review
    case videoPreview(id: String)

    var id: String {
        switch self {
        case .review: "review"
        case .videoPreview(let id): "video:\(id)"
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
        case .compare, .swipe: true
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
