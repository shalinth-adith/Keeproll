import Foundation
import Testing
@testable import Sift

@MainActor
struct ScreenshotsViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func loadedStore(_ items: [MediaItem]) async -> ScanStore {
        let store = Fixtures.scanStore(screenshots: items)
        store.scan()
        // Wait for the scan task to publish results.
        for _ in 0..<100 where store.screenshots.value == nil { await Task.yield() }
        return store
    }

    @Test func olderThan30DaysFilter() async {
        let store = await loadedStore([
            Fixtures.screenshot("new", daysAgo: 2, now: now),
            Fixtures.screenshot("old", daysAgo: 45, now: now),
        ])
        let vm = ScreenshotsViewModel(scanStore: store, cart: CleanupCart(), now: { now })
        #expect(vm.items.count == 2)
        vm.filter = .olderThan30Days
        #expect(vm.items.map(\.id) == ["old"])
    }

    @Test func selectAllTogglesOnlyVisibleItems() async {
        let store = await loadedStore([
            Fixtures.screenshot("new", bytes: 10, daysAgo: 2, now: now),
            Fixtures.screenshot("old", bytes: 20, daysAgo: 45, now: now),
        ])
        let cart = CleanupCart()
        let vm = ScreenshotsViewModel(scanStore: store, cart: cart, now: { now })
        vm.filter = .olderThan30Days

        vm.toggleSelectAll()
        #expect(cart.contains(assetID: "old"))
        #expect(!cart.contains(assetID: "new"))
        #expect(vm.allVisibleSelected)

        vm.toggleSelectAll()
        #expect(cart.isEmpty)
    }

    @Test func deniedPermissionLeavesScreenshotsIdle() async {
        let store = Fixtures.scanStore(screenshots: [Fixtures.screenshot("a")], photos: .denied)
        store.scan()
        for _ in 0..<20 { await Task.yield() }
        #expect(store.screenshots.value == nil)
    }
}
