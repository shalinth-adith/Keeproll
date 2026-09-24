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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        lifetimeBytesFreed = (defaults.object(forKey: Keys.lifetimeBytes) as? NSNumber)?.int64Value ?? 0
    }

    func recordFreed(_ bytes: Int64) {
        lifetimeBytesFreed += max(bytes, 0)
        WidgetBridge.update(lifetimeFreedBytes: lifetimeBytesFreed)
    }

    private enum Keys {
        static let onboarding = "hasCompletedOnboarding"
        static let lifetimeBytes = "lifetimeBytesFreed"
    }
}
