import Foundation
import Testing
import UIKit
@testable import Sift

/// Regression tests for the findings in docs/TEST_REPORT.md.
@MainActor
struct RegressionTests {
    // MARK: F1 — a reused thumbnail must never show another photo's image

    @Test func thumbnailNeverShowsAnImageLoadedForADifferentPhoto() {
        let photoA = UIImage()
        let cachedB = UIImage()
        let loadedForA = LoadedThumbnail(id: "A", image: photoA)

        // The swipe card moved from A to B, and B is already in the memory cache.
        #expect(LoadedThumbnail.image(for: "B", loaded: loadedForA, cached: cachedB) === cachedB)
        // B isn't cached yet: show nothing rather than A.
        #expect(LoadedThumbnail.image(for: "B", loaded: loadedForA, cached: nil) == nil)
        // Still on A: its own image.
        #expect(LoadedThumbnail.image(for: "A", loaded: loadedForA, cached: nil) === photoA)
    }

    // MARK: F2 — the user's Best survives a rescan; Sift's own deletes don't mark stale

    private func photo(_ id: String, _ bytes: Int64) -> MediaItem {
        MediaItem(id: id, kind: .photo, creationDate: Date(timeIntervalSince1970: 1_000), pixelWidth: 4000, pixelHeight: 3000,
                  duration: nil, isFavorite: false, byteSize: bytes)
    }

    private func settle(_ store: ScanStore) async {
        for _ in 0..<400 where store.isScanning || store.similarProgress != nil { await Task.yield() }
    }

    @Test func manualBestSurvivesARescan() async {
        let groupID = UUID()
        // The engine always ranks "a" as best, as a real rescan would.
        let scanned = SimilarGroup(id: groupID, kind: .similar, members: [photo("a", 300), photo("b", 200), photo("c", 100)], bestID: "a")
        let defaults = UserDefaults(suiteName: "SiftTests-\(UUID().uuidString)")!
        let store = Fixtures.scanStore(screenshots: [], similarity: FakeSimilarity(events: [.upsert(scanned)]), defaults: defaults)
        store.scan()
        await settle(store)

        store.setBest("b", in: groupID)
        #expect(store.similar.value?.first?.bestID == "b")

        store.scan() // e.g. the foreground refresh after a delete
        await settle(store)
        let group = store.similar.value?.first
        #expect(group?.bestID == "b")
        #expect(group?.members.first?.id == "b")
        #expect(group?.othersThanBest.map(\.id).contains("b") == false) // never offered for deletion

        // And it survives an app relaunch (a new store on the same defaults).
        let relaunched = Fixtures.scanStore(screenshots: [], similarity: FakeSimilarity(events: [.upsert(scanned)]), defaults: defaults)
        relaunched.scan()
        await settle(relaunched)
        #expect(relaunched.similar.value?.first?.bestID == "b")
    }

    @Test func choosingAgainInTheSameGroupReplacesTheEarlierChoice() async {
        let groupID = UUID()
        let scanned = SimilarGroup(id: groupID, kind: .similar, members: [photo("a", 300), photo("b", 200), photo("c", 100)], bestID: "a")
        let store = Fixtures.scanStore(screenshots: [], similarity: FakeSimilarity(events: [.upsert(scanned)]))
        store.scan()
        await settle(store)
        store.setBest("b", in: groupID)
        store.setBest("c", in: groupID)
        #expect(store.bestOverrides.contains("c"))
        #expect(!store.bestOverrides.contains("b"))
    }

    @Test func siftsOwnDeletionDoesNotTriggerARescan() async {
        let store = Fixtures.scanStore(screenshots: [Fixtures.screenshot("x")])
        store.scan()
        await settle(store)
        let now = Date()
        store.expectOwnChanges(now: now)
        store.apply(LibraryDelta(removedIDs: ["x"], hasAdditionsOrEdits: true), now: now.addingTimeInterval(2))
        #expect(!store.isStale)
        #expect(store.screenshots.value?.isEmpty == true) // the removal itself still applies

        // Later, a real new photo does mark results stale.
        store.apply(LibraryDelta(removedIDs: [], hasAdditionsOrEdits: true), now: now.addingTimeInterval(30))
        #expect(store.isStale)
    }
}

struct CopyRegressionTests {
    // F8: never "Zero KB".
    @Test func zeroBytesIsNumeric() {
        let text = ByteFormatter.string(0)
        #expect(text.first?.isNumber == true, "got \(text)")
        #expect(!text.localizedCaseInsensitiveContains("zero"))
        #expect(ByteFormatter.string(-5) == text)
        #expect(ByteFormatter.string(1_400_000_000).contains("1.4"))
    }
}
