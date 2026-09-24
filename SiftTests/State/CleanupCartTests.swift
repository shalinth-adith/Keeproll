import Testing
@testable import Sift

@MainActor
struct CleanupCartTests {
    @Test func toggleAddsThenRemoves() {
        let cart = CleanupCart()
        let item = CartItem.asset(id: "a", category: .screenshots, bytes: 100)
        cart.toggle(item)
        #expect(cart.contains(assetID: "a"))
        #expect(cart.totalBytes == 100)
        cart.toggle(item)
        #expect(cart.isEmpty)
    }

    @Test func sameAssetFromTwoCategoriesCountsOnce() {
        // FR-CART-2: an asset selected in two places is counted once.
        let cart = CleanupCart()
        cart.add([.asset(id: "a", category: .similar, bytes: 100)])
        cart.add([.asset(id: "a", category: .screenshots, bytes: 100)])
        #expect(cart.count == 1)
        #expect(cart.totalBytes == 100)
    }

    @Test func perCategoryTotals() {
        let cart = CleanupCart()
        cart.add([
            .asset(id: "a", category: .screenshots, bytes: 100),
            .asset(id: "b", category: .screenshots, bytes: 50),
            .asset(id: "c", category: .videos, bytes: 1_000),
        ])
        #expect(cart.bytes(in: .screenshots) == 150)
        #expect(cart.count(in: .videos) == 1)
        cart.removeAll(in: .screenshots)
        #expect(cart.count == 1)
    }
}
