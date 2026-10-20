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
    var forecast: StorageForecast { scanStore.storageForecast }
    /// Free bytes per day over the forecast window, oldest first, for the sparkline.
    var forecastPoints: [Int64] {
        let cutoff = Date().addingTimeInterval(-Double(StorageForecaster.windowDays) * 86_400)
        return scanStore.storageHistory.filter { $0.date >= cutoff }.map(\.availableBytes)
    }

    /// "Scanning…", "Just now", "2 hours ago", or "Not yet". Photos locked means no
    /// photo scan has happened, whatever contacts did (QA L3).
    var lastScanLabel: String {
        if photosLocked { return String(localized: "Not yet") }
        if isScanning { return String(localized: "Scanning…") }
        guard let date = lastScanDate else { return String(localized: "Not yet") }
        if Date().timeIntervalSince(date) < 60 { return String(localized: "Just now") }
        // Sentence case: "8 minutes ago", not "8 Minutes Ago" (UX review P3-1).
        return date.formatted(Date.RelativeFormatStyle(presentation: .named, capitalizationContext: .beginningOfSentence))
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

    /// What the ring draws as freeable: one de-duplicated total, to scale (UX review P1-4).
    /// Per-category arcs added up overlapping photos and needed a fake minimum size.
    var segments: [StorageSegment] {
        [StorageSegment(id: "freeable", label: "Can be freed", bytes: totalFreeable, color: Color.keeproll.warning)]
    }

    /// One line describing what the category looks for; the locked state where it applies.
    func checkSubtitle(for category: CleanupCategory) -> LocalizedStringResource {
        // Photo rows say they're locked, like Contacts and Calendar do (QA M7).
        if photosLocked && category.needsPhotoLibrary { return "Needs access · tap to allow" }
        return switch category {
        case .similar: "Bursts and duplicate shots"
        case .screenshots: "Screenshots taking up space"
        case .blurry: "Out-of-focus photos"
        case .accidental: "Pocket shots and black frames"
        case .videos: "Biggest clips, compressible"
        case .trims: "Cut dark parts of videos"
        case .chats: "Forwards from chat apps"
        case .expired: "Old codes, passes and tickets"
        case .livePhotos: "Keep the still, drop the clip"
        case .contacts: scanStore.contactsPermission.canRead ? "The same person saved twice" : "Needs access · tap to allow"
        case .calendar: scanStore.calendarPermission.canRead ? "Duplicates and events over a year old" : "Needs access · tap to allow"
        case .vault: "Photos kept behind Face ID"
        }
    }

    /// Last-known number for a category row, if any. Contacts and calendar have no size, so
    /// their count carries its noun: a bare "4" next to "2.5 MB" read as a size (UX review P2-2).
    func chipValue(for category: CleanupCategory) -> Text? {
        guard let count = scanStore.displayCount(category), count > 0 else { return nil }
        switch category {
        case .contacts: return Text("^[\(count) duplicate](inflect: true)")
        case .calendar: return Text("^[\(count) event](inflect: true)")
        default: return scanStore.displayBytes(category).map { Text(ByteFormatter.string($0)) }
        }
    }

    /// Categories largest first: photo categories by size, then contacts and calendar by
    /// count, then the ones with nothing to clean, in their usual order (UX review P2-2).
    var sortedCategories: [CleanupCategory] {
        func rank(_ category: CleanupCategory) -> (Int, Int64) {
            let count = scanStore.displayCount(category) ?? 0
            guard count > 0 else { return (2, 0) }
            if category == .contacts || category == .calendar { return (1, Int64(count)) }
            return (0, scanStore.displayBytes(category) ?? 0)
        }
        return categories.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra.0 != rb.0 { return ra.0 < rb.0 }
            if ra.1 != rb.1 { return ra.1 > rb.1 }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// How many rows Home shows once there are results. Results is the full list, so Home
    /// keeps to the few that matter most (UX review P2-1).
    static let homeRowLimit = 3

    /// Home's rows: the biggest few after a scan, every category before one (so a new user
    /// sees what Keeproll checks), or while photos are locked (each row says how to unlock).
    var homeCategories: [CleanupCategory] {
        guard hasResults, !photosLocked else { return categories }
        let withFindings = sortedCategories.filter { (scanStore.displayCount($0) ?? 0) > 0 }
        return Array((withFindings.isEmpty ? sortedCategories : withFindings).prefix(Self.homeRowLimit))
    }

    /// Rows Home leaves out, for the "See all" link.
    var hiddenCategoryCount: Int { categories.count - homeCategories.count }

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
    func openSwipe() { router.open(.swipe) }
    func openVault() { router.open(.vault) }
    func open(_ category: CleanupCategory) {
        // A locked photo row opens Results, which explains the lock and offers access,
        // instead of jumping straight to iOS Settings (QA M7).
        guard scanStore.photosPermission.canRead || !category.needsPhotoLibrary else { router.showDashboard(); return }
        switch category {
        case .similar: router.open(.similar)
        case .screenshots: router.open(.screenshots)
        case .blurry: router.open(.blurry)
        case .accidental: router.open(.accidental)
        case .videos: router.open(.videos)
        case .trims: router.open(.trims)
        case .chats: router.open(.chats)
        case .expired: router.open(.expired)
        case .livePhotos: router.open(.livePhotos)
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
