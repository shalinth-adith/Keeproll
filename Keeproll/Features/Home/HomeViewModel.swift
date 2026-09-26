import Observation
import SwiftUI

/// The entry screen: device storage, one call to action, and a glance at what the last
/// scan found (DESIGN_SYSTEM §9, Home).
@Observable
final class HomeViewModel {
    private let scanStore: ScanStore
    private let router: AppRouter
    let settings: SettingsStore

    init(scanStore: ScanStore, router: AppRouter, settings: SettingsStore) {
        self.scanStore = scanStore
        self.router = router
        self.settings = settings
    }

    var storage: StorageSnapshot? { scanStore.storage.value }
    var isScanning: Bool { scanStore.isScanning }
    var scanProgress: Double? { scanStore.similarProgress }
    var photosLocked: Bool { !scanStore.photosPermission.canRead }
    var photosPermission: PermissionState { scanStore.photosPermission }
    var lastScanDate: Date? { scanStore.lastSummary?.finishedAt }

    /// "Scanning…", "Just now", "2 hours ago", or "Not yet".
    var lastScanLabel: String {
        if isScanning { return String(localized: "Scanning…") }
        guard let date = lastScanDate else { return String(localized: "Not yet") }
        if Date().timeIntervalSince(date) < 60 { return String(localized: "Just now") }
        return date.formatted(.relative(presentation: .named)).localizedCapitalized
    }
    var categories: [CleanupCategory] { scanStore.availableCategories }

    /// True once any scan has produced numbers (this launch or a previous one).
    var hasResults: Bool { scanStore.lastSummary != nil || scanStore.totalFreeableBytes > 0 }

    var totalFreeable: Int64 {
        scanStore.isScanning ? max(scanStore.totalFreeableBytes, scanStore.lastSummary?.totalFreeable ?? 0)
                             : scanStore.totalFreeableBytes
    }

    /// Count of categories with something to clean, for the results card.
    var categoriesWithFindings: Int {
        categories.filter { (scanStore.displayCount($0) ?? 0) > 0 }.count
    }

    var segments: [StorageSegment] {
        categories.compactMap { category in
            switch category {
            case .similar: StorageSegment(id: "similar", label: "Similar", bytes: scanStore.displayBytes(.similar) ?? 0, color: Color.keeproll.catSimilar)
            case .screenshots: StorageSegment(id: "screenshots", label: "Screenshots", bytes: scanStore.displayBytes(.screenshots) ?? 0, color: Color.keeproll.catScreenshots)
            case .blurry: StorageSegment(id: "blurry", label: "Blurry", bytes: scanStore.displayBytes(.blurry) ?? 0, color: Color.keeproll.catBlurry)
            case .videos: StorageSegment(id: "videos", label: "Videos", bytes: scanStore.displayBytes(.videos) ?? 0, color: Color.keeproll.catVideos)
            case .contacts, .calendar, .vault: nil
            }
        }
    }

    /// One line describing what the category looks for; the locked state where it applies.
    func checkSubtitle(for category: CleanupCategory) -> LocalizedStringResource {
        switch category {
        case .similar: "Bursts and duplicate shots"
        case .screenshots: "Screenshots taking up space"
        case .blurry: "Out-of-focus photos"
        case .videos: "Biggest clips, compressible"
        case .contacts: scanStore.contactsPermission.canRead ? "The same person saved twice" : "Needs access · tap to allow"
        case .calendar: scanStore.calendarPermission.canRead ? "Duplicates and events over a year old" : "Needs access · tap to allow"
        case .vault: "Photos kept behind Face ID"
        }
    }

    /// Last-known number for a category chip, if any.
    func chipValue(for category: CleanupCategory) -> String? {
        guard let count = scanStore.displayCount(category), count > 0 else { return nil }
        if category == .contacts || category == .calendar { return "\(count)" }
        return scanStore.displayBytes(category).map(ByteFormatter.string)
    }

    func onAppear() {
        if case .idle = scanStore.storage { scanStore.scan() }
    }

    /// Primary action: start a scan if there are no results yet, otherwise show them.
    func primaryAction() {
        if !hasResults && !isScanning { scanStore.scan() }
        router.showDashboard()
    }

    func rescan() { scanStore.scan() }
    func openSettings() { router.open(.settings) }
    func open(_ category: CleanupCategory) {
        let asksForItsOwnAccess = category == .contacts || category == .calendar
        guard scanStore.photosPermission.canRead || asksForItsOwnAccess else { SystemActions.openSettings(); return }
        switch category {
        case .similar: router.open(.similar)
        case .screenshots: router.open(.screenshots)
        case .blurry: router.open(.blurry)
        case .videos: router.open(.videos)
        case .contacts: router.open(.contacts)
        case .calendar: router.open(.calendar)
        case .vault: router.open(.vault)
        }
    }

    func requestPhotosAccess() async {
        if scanStore.photosPermission == .notDetermined {
            await scanStore.requestPhotos()
            scanStore.scan()
        } else {
            SystemActions.openSettings()
        }
    }
}
