import Testing
@testable import Keeproll

@MainActor
struct ReviewViewModelTests {
    private func makeVM(_ behaviour: FakeDeletion.Behaviour, cart: CleanupCart) -> (ReviewViewModel, FakeDeletion, SettingsStore) {
        let deletion = FakeDeletion(behaviour)
        let settings = Fixtures.settings()
        let store = Fixtures.scanStore(screenshots: [])
        return (ReviewViewModel(cart: cart, deletion: deletion, scanStore: store, settings: settings), deletion, settings)
    }

    @Test func confirmDeletesExactlyTheCartContents() async {
        let cart = CleanupCart()
        cart.add([.asset(id: "a", category: .screenshots, bytes: 100), .asset(id: "b", category: .screenshots, bytes: 200)])
        let (vm, deletion, settings) = makeVM(.deleteAll, cart: cart)

        await vm.confirm()

        let plans = await deletion.executedPlans
        #expect(plans.count == 1)
        #expect(Set(plans[0].assetIDs) == ["a", "b"])
        #expect(cart.isEmpty)
        #expect(settings.lifetimeBytesFreed == 300)
        guard case .finished(let result) = vm.phase else { Issue.record("Expected finished phase"); return }
        #expect(result.bytesFreed == 300)
    }

    @Test func cancellingTheSystemPromptKeepsTheCart() async {
        // FR-REV-5: nothing deleted, cart unchanged.
        let cart = CleanupCart()
        cart.add([.asset(id: "a", category: .screenshots, bytes: 100)])
        let (vm, _, settings) = makeVM(.cancel, cart: cart)

        await vm.confirm()

        #expect(cart.count == 1)
        #expect(vm.phase == .reviewing)
        #expect(settings.lifetimeBytesFreed == 0)
    }

    @Test func emptyCartNeverCallsDeletion() async {
        let (vm, deletion, _) = makeVM(.deleteAll, cart: CleanupCart())
        await vm.confirm()
        #expect(await deletion.executedPlans.isEmpty)
    }

    @Test func removingAnItemOnReviewExcludesItFromThePlan() async {
        let cart = CleanupCart()
        cart.add([.asset(id: "a", category: .screenshots, bytes: 100), .asset(id: "b", category: .screenshots, bytes: 200)])
        let (vm, deletion, _) = makeVM(.deleteAll, cart: cart)

        vm.remove(assetID: "a")
        await vm.confirm()

        #expect(await deletion.executedPlans.first?.assetIDs == ["b"])
    }
}
