import Foundation
import Observation

/// Small persisted settings. Scan results live in `ScanCache`, not here.
@Observable
final class SettingsStore {
    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    /// Running total shown on the dashboard (FR-SUM-2).
    private(set) var lifetimeBytesFreed: Int64 {
        didSet { defaults.set(lifetimeBytesFreed, forKey: Keys.lifetimeBytes) }
    }

    /// Launches so far; the review prompt never fires in the first one.
    private(set) var sessionCount: Int {
        didSet { defaults.set(sessionCount, forKey: Keys.sessions) }
    }

    /// The review sheet is asked for once per install, ever.
    private(set) var hasAskedForReview: Bool {
        didSet { defaults.set(hasAskedForReview, forKey: Keys.askedReview) }
    }

    /// Build number the user last saw a What's New for; nil until onboarding finishes.
    var lastSeenBuild: String? {
        didSet { defaults.set(lastSeenBuild, forKey: Keys.lastSeenBuild) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        lifetimeBytesFreed = (defaults.object(forKey: Keys.lifetimeBytes) as? NSNumber)?.int64Value ?? 0
        sessionCount = defaults.integer(forKey: Keys.sessions)
        hasAskedForReview = defaults.bool(forKey: Keys.askedReview)
        lastSeenBuild = defaults.string(forKey: Keys.lastSeenBuild)
    }

    func recordSession() { sessionCount += 1 }
    func markReviewAsked() { hasAskedForReview = true }

    /// Settings → "Reset freed total".
    func resetFreedTotal() {
        lifetimeBytesFreed = 0
        WidgetBridge.update(lifetimeFreedBytes: 0)
    }

    func recordFreed(_ bytes: Int64) {
        lifetimeBytesFreed += max(bytes, 0)
        WidgetBridge.update(lifetimeFreedBytes: lifetimeBytesFreed)
    }

    private enum Keys {
        static let onboarding = "hasCompletedOnboarding"
        static let lifetimeBytes = "lifetimeBytesFreed"
        static let sessions = "sessionCount"
        static let askedReview = "hasAskedForReview"
        static let lastSeenBuild = "lastSeenBuild"
    }
}
