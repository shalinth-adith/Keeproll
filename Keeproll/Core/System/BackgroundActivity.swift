import UIKit

/// Asks iOS for extra time to finish work if the user leaves the app mid-way
/// (vault imports, video compression). Ending twice is safe.
@MainActor
final class BackgroundActivity {
    private var id: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    static func begin(_ name: String) -> BackgroundActivity {
        let activity = BackgroundActivity()
        activity.id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak activity] in
            // Out of time: end it so iOS doesn't terminate the app.
            MainActor.assumeIsolated { activity?.end() }
        }
        Log.ui.debug("Background activity began: \(name, privacy: .public)")
        return activity
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
