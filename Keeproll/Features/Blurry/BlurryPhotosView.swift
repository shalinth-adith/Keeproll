import Observation
import SwiftUI

/// Photos whose sharpness score falls below the blur threshold (bonus: blurry detection).
/// The scores come free from the similarity scan, so this costs no extra analysis.
@Observable
final class BlurryPhotosViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    var items: [MediaItem] { scanStore.blurry.value ?? [] }
    var isScanning: Bool { scanStore.similarProgress != nil }
    var totalBytes: Int64 { scanStore.blurryBytes }
    var selectedCount: Int { items.filter { cart.contains(assetID: $0.id) }.count }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy { cart.contains(assetID: $0.id) } }

    func isSelected(_ item: MediaItem) -> Bool { cart.contains(assetID: item.id) }

    func setSelected(_ item: MediaItem, _ selected: Bool) {
        if selected { cart.add([item.cartItem(in: .blurry)]) } else { cart.removeAssets([item.id]) }
    }

    func toggleAll() {
        if allSelected { cart.removeAssets(items.map(\.id)) } else { cart.add(items.map { $0.cartItem(in: .blurry) }) }
    }
}

struct BlurryPhotosView: View {
    @State private var vm: BlurryPhotosViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: BlurryPhotosViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                if vm.items.isEmpty {
                    if !vm.isScanning {
                        EmptyState(systemImage: "camera.metering.unknown", title: Text("No blurry photos"),
                                   message: Text("Every photo Keeproll checked looks sharp."))
                    }
                } else {
                    SelectableMediaGrid(
                        items: vm.items,
                        isSelected: vm.isSelected,
                        setSelected: vm.setSelected,
                        accessibilityLabel: { item in
                            Text("Blurry photo, \(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""), \(ByteFormatter.string(item.byteSize ?? 0))\(vm.isSelected(item) ? ", selected" : "")")
                        }
                    )
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Blurry Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.allSelected ? "Deselect all" : "Select all") { vm.toggleAll() }
                    .disabled(vm.items.isEmpty)
            }
        }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalBytes)),
            caption: Text("^[\(vm.items.count) photo](inflect: true) out of focus"),
            selectedCount: vm.selectedCount,
            hint: HintRow("heart", Text("Favourites are never suggested. Drag sideways to select several at once.")),
            scanning: vm.isScanning && vm.items.isEmpty ? Text("Checking photos for blur…") : nil
        )
        .animation(Motion.standard, value: vm.totalBytes)
    }
}
