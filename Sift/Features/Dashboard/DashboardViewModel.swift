import Observation
import SwiftUI

@Observable
final class DashboardViewModel {
    private let scanStore: ScanStore
    private let router: AppRouter
    let settings: SettingsStore

    init(scanStore: ScanStore, router: AppRouter, settings: SettingsStore) {
        self.scanStore = scanStore
        self.router = router
        self.settings = settings
    }

    var storage: StorageSnapshot? { scanStore.storage.value }
    var photosPermission: PermissionState { scanStore.photosPermission }
    var showLimitedBanner: Bool { scanStore.photosPermission == .limited }
    var showPhotosLocked: Bool { !scanStore.photosPermission.canRead }

    /// Categories shipped so far. Others are added as their scanners land (PRD §9).
    let categories: [CleanupCategory] = [.screenshots]

    var segments: [StorageSegment] {
        [StorageSegment(id: "screenshots", label: "Screenshots", bytes: scanStore.screenshotBytes, color: Color.sift.catScreenshots)]
    }

    func cardState(for category: CleanupCategory) -> CategoryCard.State {
        guard scanStore.photosPermission.canRead else { return .locked }
        switch category {
        case .screenshots:
            switch scanStore.screenshots {
            case .idle, .loading: return .scanning
            case .failed: return .empty
            case .loaded(let items):
                return items.isEmpty ? .empty : .ready(bytes: scanStore.screenshotBytes, count: items.count)
            }
        default:
            return .scanning
        }
    }

    func open(_ category: CleanupCategory) {
        guard scanStore.photosPermission.canRead else {
            SystemActions.openSettings()
            return
        }
        switch category {
        case .screenshots: router.open(.screenshots)
        default: break
        }
    }

    func onAppear() {
        if case .idle = scanStore.storage { scanStore.scan() }
    }

    func rescan() { scanStore.scan() }

    func requestPhotosAccess() async {
        if scanStore.photosPermission == .notDetermined {
            await scanStore.requestPhotos()
            scanStore.scan()
        } else {
            SystemActions.openSettings()
        }
    }

    func addMorePhotos() async {
        await SystemActions.presentLimitedLibraryPicker()
        scanStore.scan()
    }
}
