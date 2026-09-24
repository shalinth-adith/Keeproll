import Observation

enum Route: Hashable {
    case screenshots
}

enum Sheet: String, Identifiable {
    case review
    var id: String { rawValue }
}

@Observable
final class AppRouter {
    var path: [Route] = []
    var sheet: Sheet?

    func open(_ route: Route) { path.append(route) }
    func presentReview() { sheet = .review }

    /// After cleaning, go back to the dashboard.
    func finishCleanup() {
        sheet = nil
        path.removeAll()
    }
}
