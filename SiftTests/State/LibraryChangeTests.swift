import Foundation
import Testing
@testable import Sift

@MainActor
struct LibraryChangeTests {
    private func loadedStore() async -> ScanStore {
        let store = Fixtures.scanStore(screenshots: [Fixtures.screenshot("a"), Fixtures.screenshot("b")])
        store.scan()
        for _ in 0..<200 where store.isScanning { await Task.yield() }
        return store
    }

    @Test func photosDeletedElsewhereDisappearAtOnce() async {
        let store = await loadedStore()
        let removed = store.apply(LibraryDelta(removedIDs: ["a", "not-shown"], hasAdditionsOrEdits: false))
        #expect(removed == ["a"]) // only ids Sift was showing
        #expect(store.screenshots.value?.map(\.id) == ["b"])
        #expect(!store.isStale)
    }

    @Test func additionsMarkResultsStaleWithoutRescanning() async {
        let store = await loadedStore()
        store.apply(LibraryDelta(removedIDs: [], hasAdditionsOrEdits: true))
        #expect(store.isStale)
        #expect(!store.isScanning) // no surprise rescan under the user's finger
        #expect(store.screenshots.value?.count == 2)
    }

    @Test func rescanClearsStaleness() async {
        let store = await loadedStore()
        store.apply(LibraryDelta(removedIDs: [], hasAdditionsOrEdits: true))
        store.scan()
        #expect(!store.isStale)
    }
}
