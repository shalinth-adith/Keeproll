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

    /// Categories with a scanner in this build.
    var categories: [CleanupCategory] { scanStore.availableCategories }

    var showSwipeEntry: Bool {
        scanStore.similarPhotoCount + (scanStore.screenshots.value?.count ?? 0) + (scanStore.blurry.value?.count ?? 0) > 0
    }

    /// Freeable total with each asset counted once (FR-DASH-6); the last scan's total
    /// until this one finishes.
    var totalFreeable: Int64 {
        scanStore.isScanning ? max(scanStore.totalFreeableBytes, scanStore.lastSummary?.totalFreeable ?? 0)
                             : scanStore.totalFreeableBytes
    }

    /// New or edited photos arrived while the app was open.
    var showStaleBanner: Bool { scanStore.isStale && !scanStore.isScanning }

    /// Progress of the long photo scan, for the hero (nil when idle).
    var scanProgress: Double? { scanStore.similarProgress }

    /// The card shows last-known numbers while a fresh scan runs.
    func isRefreshing(_ category: CleanupCategory) -> Bool {
        scanStore.isScanning && !scanStore.isLoaded(category) && scanStore.lastSummary?.counts[category.rawValue] != nil
    }

    var segments: [StorageSegment] {
        categories.compactMap { category in
            switch category {
            case .similar: StorageSegment(id: "similar", label: "Similar", bytes: scanStore.displayBytes(.similar) ?? 0, color: Color.sift.catSimilar)
            case .screenshots: StorageSegment(id: "screenshots", label: "Screenshots", bytes: scanStore.displayBytes(.screenshots) ?? 0, color: Color.sift.catScreenshots)
            case .blurry: StorageSegment(id: "blurry", label: "Blurry", bytes: scanStore.displayBytes(.blurry) ?? 0, color: Color.sift.catBlurry)
            case .videos: StorageSegment(id: "videos", label: "Videos", bytes: scanStore.displayBytes(.videos) ?? 0, color: Color.sift.catVideos)
            case .contacts: nil // bytes are negligible (FR-DASH-2)
            }
        }
    }

    func cardState(for category: CleanupCategory) -> CategoryCard.State {
        // While refreshing, keep showing the last scan's numbers instead of a spinner.
        if isRefreshing(category), let bytes = scanStore.displayBytes(category), let count = scanStore.displayCount(category) {
            let permitted = category == .contacts ? scanStore.contactsPermission.canRead : scanStore.photosPermission.canRead
            if permitted { return count == 0 ? .empty : .ready(bytes: bytes, count: count) }
        }
        switch category {
        case .screenshots:
            guard scanStore.photosPermission.canRead else { return .locked }
            return state(scanStore.screenshots, bytes: scanStore.screenshotBytes) { $0.count }
        case .videos:
            guard scanStore.photosPermission.canRead else { return .locked }
            return state(scanStore.videos, bytes: scanStore.videoBytes) { $0.count }
        case .similar:
            guard scanStore.photosPermission.canRead else { return .locked }
            if let progress = scanStore.similarProgress, scanStore.similarPhotoCount == 0 { return .scanning(progress: progress) }
            return state(scanStore.similar, bytes: scanStore.similarBytes) { _ in scanStore.similarPhotoCount }
        case .blurry:
            guard scanStore.photosPermission.canRead else { return .locked }
            if let progress = scanStore.similarProgress, (scanStore.blurry.value ?? []).isEmpty { return .scanning(progress: progress) }
            return state(scanStore.blurry, bytes: scanStore.blurryBytes) { $0.count }
        case .contacts:
            guard scanStore.contactsPermission.canRead else { return .locked }
            return state(scanStore.contacts, bytes: 0) { _ in scanStore.duplicateContactCount }
        }
    }

    private func state<T>(_ loadable: Loadable<[T]>, bytes: Int64, count: ([T]) -> Int) -> CategoryCard.State {
        switch loadable {
        case .idle, .loading: return .scanning(progress: nil)
        case .failed: return .empty
        case .loaded(let items):
            return items.isEmpty ? .empty : .ready(bytes: bytes, count: count(items))
        }
    }

    func open(_ category: CleanupCategory) {
        let permission = category == .contacts ? scanStore.contactsPermission : scanStore.photosPermission
        guard permission.canRead || category == .contacts else {
            SystemActions.openSettings()
            return
        }
        switch category {
        case .similar: router.open(.similar)
        case .screenshots: router.open(.screenshots)
        case .blurry: router.open(.blurry)
        case .videos: router.open(.videos)
        case .contacts: router.open(.contacts)
        }
    }

    func openSwipe() { router.open(.swipe) }
    func openCalibration() { router.open(.calibration) }

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
