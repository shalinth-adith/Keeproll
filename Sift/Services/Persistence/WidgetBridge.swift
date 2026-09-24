import Foundation
import WidgetKit

/// Pushes scan results to the Home Screen widget (bonus B5).
nonisolated enum WidgetBridge {
    static func update(freeableBytes: Int64? = nil, lifetimeFreedBytes: Int64? = nil) {
        var snapshot = WidgetSnapshot.load()
        if let freeableBytes { snapshot.freeableBytes = freeableBytes }
        if let lifetimeFreedBytes { snapshot.lifetimeFreedBytes = lifetimeFreedBytes }
        snapshot.updatedAt = Date()
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
