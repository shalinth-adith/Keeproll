import Foundation
import PhotosUI
import Testing
@testable import Keeproll

// MARK: - Calendar cleanup

struct CalendarCleanupFinderTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ id: String, _ title: String, daysAgo: Double, hours: Double = 1,
                       calendar: String = "Home", allDay: Bool = false) -> CalendarEventSummary {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return CalendarEventSummary(id: id, title: title, start: start, end: start.addingTimeInterval(hours * 3600),
                                    calendarTitle: calendar, isAllDay: allDay)
    }

    @Test func identicalEventsGroupAndTheFirstIsKept() {
        let findings = CalendarCleanupFinder.find([
            event("a", "Dentist", daysAgo: 10),
            event("b", " dentist ", daysAgo: 10, calendar: "Work"), // same title, time: duplicate
            event("c", "Dentist", daysAgo: 11),                     // different day: not a duplicate
        ], now: now)
        #expect(findings.duplicateGroups.count == 1)
        #expect(findings.duplicateGroups[0].map(\.id) == ["a", "b"])
        #expect(findings.extraCopies.map(\.id) == ["b"]) // "a" is kept
    }

    @Test func onlyEventsOverAYearOldAreOld() {
        let findings = CalendarCleanupFinder.find([
            event("recent", "Lunch", daysAgo: 300),
            event("old", "Conference", daysAgo: 400),
            event("older", "Wedding", daysAgo: 900),
        ], now: now)
        #expect(findings.oldEvents.map(\.id) == ["old", "older"]) // newest first
    }

    @Test func duplicatesAreNotAlsoListedAsOld() {
        let findings = CalendarCleanupFinder.find([
            event("a", "Trip", daysAgo: 500), event("b", "Trip", daysAgo: 500),
        ], now: now)
        #expect(findings.oldEvents.isEmpty)
        #expect(findings.suggestionCount == 1)
    }

    @Test func removingDeletedEventsUpdatesFindings() {
        let findings = CalendarCleanupFinder.find([
            event("a", "Trip", daysAgo: 20), event("b", "Trip", daysAgo: 20), event("old", "Old", daysAgo: 800),
        ], now: now)
        let after = findings.removing(["b", "old"])
        #expect(after.duplicateGroups.isEmpty) // a lone event isn't a duplicate
        #expect(after.oldEvents.isEmpty)
    }

    @Test func icsBackupIsValidAndEscaped() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let text = ICSWriter.document([
            ICSWriter.Event(uid: "u1", title: "Lunch; with, Priya", start: start, end: start.addingTimeInterval(3600),
                            isAllDay: false, location: "Café\nUpstairs", notes: nil, url: nil),
        ])
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
        #expect(text.contains(#"SUMMARY:Lunch\; with\, Priya"#))
        #expect(text.contains(#"LOCATION:Café\nUpstairs"#))
        #expect(text.contains("DTSTART:20231114T221320Z"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        // Long lines are folded to 75 octets.
        let long = ICSWriter.fold(String(repeating: "x", count: 200))
        #expect(long.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
    }
}

/// Records what it was asked to remove.
actor FakeCalendarMutator: CalendarMutating {
    private(set) var removed: [String] = []
    func delete(_ events: [CleanupPlan.CalendarEvent]) async -> (backup: URL?, failures: [CleanupFailure]) {
        removed += events.map(\.id)
        return (URL(fileURLWithPath: "/tmp/calendar-backup.ics"), [])
    }
}

@MainActor
struct CalendarReviewTests {
    @Test func approvedEventsGoThroughTheDeletionServiceWithABackup() async {
        let cart = CleanupCart()
        cart.add([.calendarEvent(id: "e1", title: "Old trip", start: nil),
                  .calendarEvent(id: "e2", title: "Duplicate", start: nil)])
        let mutator = FakeCalendarMutator()
        let vm = ReviewViewModel(cart: cart, deletion: DeletionService(calendar: mutator),
                                 scanStore: Fixtures.scanStore(screenshots: []), settings: Fixtures.settings())
        await vm.confirm()

        #expect(Set(await mutator.removed) == ["e1", "e2"])
        #expect(cart.isEmpty)
        guard case .finished(let result) = vm.phase else { Issue.record("not finished"); return }
        #expect(result.countsByCategory[.calendar] == 2)
        #expect(result.backupURLs.count == 1)
        #expect(result.deletedAssetIDs.isEmpty) // no photos touched
    }

    @Test func withoutACalendarServiceNothingIsSilentlyDropped() async {
        let cart = CleanupCart()
        cart.add([.calendarEvent(id: "e1", title: "Trip", start: nil)])
        let vm = ReviewViewModel(cart: cart, deletion: DeletionService(),
                                 scanStore: Fixtures.scanStore(screenshots: []), settings: Fixtures.settings())
        await vm.confirm()
        guard case .finished(let result) = vm.phase else { Issue.record("not finished"); return }
        #expect(result.failures.count == 1)
        #expect(cart.count == 1) // still there to retry
    }
}

// MARK: - Video compression

struct CompressionEstimateTests {
    private func video(bytes: Int64, seconds: Double, width: Int = 3840, height: Int = 2160) -> MediaItem {
        MediaItem(id: "v", kind: .video, creationDate: nil, pixelWidth: width, pixelHeight: height,
                  duration: seconds, isFavorite: false, byteSize: bytes)
    }

    @Test func largeHighBitrateVideoIsWorthCompressing() {
        // 60 s of 4K at ~45 MB/min → ~39 MB after HEVC 1080p.
        let saving = VideoCompressionService.worthCompressing(video(bytes: 400_000_000, seconds: 60))
        #expect(saving != nil)
        #expect((saving ?? 0) > 300_000_000)
    }

    @Test func alreadyCompactOrSmallVideosAreNotOffered() {
        #expect(VideoCompressionService.worthCompressing(video(bytes: 30_000_000, seconds: 60)) == nil) // compact
        #expect(VideoCompressionService.worthCompressing(video(bytes: 15_000_000, seconds: 5)) == nil)  // saves < 20 MB
    }
}

// MARK: - Vault

nonisolated final class FakeVaultStore: VaultStoring, @unchecked Sendable {
    var stored: [VaultItem] = []
    func items() async -> [VaultItem] { stored }
    func importAssets(_ ids: [String], progress: @escaping @Sendable (Int, Int) -> Void) async -> VaultImportResult {
        var result = VaultImportResult()
        for id in ids {
            let item = VaultItem(id: UUID(), kind: .photo, fileName: "\(id).jpg", thumbnailName: "\(id)-t.jpg",
                                 creationDate: nil, addedAt: Date(), bytes: 1_000, duration: nil)
            stored.append(item)
            result.imported.append(item)
            result.copiedAssets.append((id, 2_000))
        }
        return result
    }
    func fileURL(for item: VaultItem) -> URL { URL(fileURLWithPath: "/tmp/\(item.fileName)") }
    func thumbnailURL(for item: VaultItem) -> URL { URL(fileURLWithPath: "/tmp/\(item.thumbnailName)") }
    func saveToPhotos(_ item: VaultItem) async throws {}
    func remove(_ items: [VaultItem]) async { stored.removeAll { items.contains($0) } }
}

nonisolated struct FakeAuth: VaultAuthenticating {
    let result: VaultUnlockResult
    func unlock() async -> VaultUnlockResult { result }
}

@MainActor
struct VaultTests {
    private func makeVM(_ auth: VaultUnlockResult, store: FakeVaultStore = FakeVaultStore(), cart: CleanupCart = CleanupCart()) -> VaultViewModel {
        VaultViewModel(store: store, auth: FakeAuth(result: auth), cart: cart, router: AppRouter())
    }

    @Test func contentsOnlyLoadAfterUnlocking() async {
        let store = FakeVaultStore()
        _ = await store.importAssets(["a"]) { _, _ in }
        let denied = makeVM(.cancelled, store: store)
        await denied.unlock()
        #expect(!denied.isUnlocked)
        #expect(denied.items.isEmpty)

        let allowed = makeVM(.unlocked, store: store)
        await allowed.unlock()
        #expect(allowed.isUnlocked)
        #expect(allowed.items.count == 1)
    }

    @Test func lockingHidesContents() async {
        let store = FakeVaultStore()
        _ = await store.importAssets(["a"]) { _, _ in }
        let vm = makeVM(.unlocked, store: store)
        await vm.unlock()
        vm.lockNow()
        #expect(!vm.isUnlocked)
        #expect(vm.items.isEmpty)
    }

    @Test func noPasscodeMeansNoVault() async {
        let vm = makeVM(.unavailable("Set a passcode"))
        await vm.unlock()
        #expect(vm.lock == .unavailable("Set a passcode"))
    }
}

@MainActor
struct CompressOfferTests {
    @Test func aVideoIsOnlyOfferedCompressionOnce() {
        let store = Fixtures.scanStore(screenshots: [])
        let vm = LargeVideosViewModel(scanStore: store, cart: CleanupCart(), router: AppRouter())
        let big = MediaItem(id: "big", kind: .video, creationDate: nil, pixelWidth: 1920, pixelHeight: 1080,
                            duration: 90, isFavorite: false, byteSize: 110_000_000)
        #expect(vm.compressSaving(for: big) != nil)
        store.markCompressed(original: "big", copy: "copy")
        #expect(vm.compressSaving(for: big) == nil)
    }
}
