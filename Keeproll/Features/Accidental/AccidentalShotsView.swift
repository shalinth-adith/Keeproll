import Observation
import SwiftUI

/// Photos taken by accident: in a pocket, with a finger over the lens, or of nothing at
/// all (bonus: Accidental Shots). The statistics come from the thumbnail the similarity
/// scan already reads, so this costs almost nothing extra.
@Observable
final class AccidentalShotsViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    var shots: [AccidentalShot] { scanStore.accidental.value ?? [] }
    var isScanning: Bool { scanStore.similarProgress != nil }
    var totalBytes: Int64 { scanStore.accidentalBytes }
    var selectedCount: Int { shots.filter { cart.contains(assetID: $0.id) }.count }
    var allSelected: Bool { !shots.isEmpty && shots.allSatisfy { cart.contains(assetID: $0.id) } }

    /// Grouped by reason, most certain first.
    var sections: [(AccidentalReason, [MediaItem])] {
        let grouped = Dictionary(grouping: shots, by: \.reason)
        return AccidentalReason.allCases.compactMap { reason in grouped[reason].map { (reason, $0.map(\.item)) } }
    }

    func isSelected(_ item: MediaItem) -> Bool { cart.contains(assetID: item.id) }
    func rescan() { scanStore.scan() }

    func setSelected(_ item: MediaItem, _ selected: Bool) {
        if selected { cart.add([item.cartItem(in: .accidental)]) } else { cart.removeAssets([item.id]) }
    }

    func toggleAll() {
        if allSelected { cart.removeAssets(shots.map(\.id)) } else { cart.add(shots.map { $0.item.cartItem(in: .accidental) }) }
    }

    func toggleSection(_ items: [MediaItem]) {
        if items.allSatisfy(isSelected) { cart.removeAssets(items.map(\.id)) } else { cart.add(items.map { $0.cartItem(in: .accidental) }) }
    }

    static func title(_ reason: AccidentalReason) -> LocalizedStringResource {
        switch reason {
        case .tooDark: "Too dark to see"
        case .finger: "Finger over the lens"
        case .blank: "Nothing in the frame"
        }
    }

    static func detail(_ reason: AccidentalReason) -> LocalizedStringResource {
        switch reason {
        case .tooDark: "Almost black, with no light anywhere: usually taken in a pocket or face down."
        case .finger: "A soft, warm blur along one edge: a fingertip in front of the camera."
        case .blank: "One flat grey with no detail, like a ceiling or the inside of a case."
        }
    }

    static func symbol(_ reason: AccidentalReason) -> String {
        switch reason {
        case .tooDark: "moon.fill"
        case .finger: "hand.point.up.left.fill"
        case .blank: "square.dashed"
        }
    }
}

struct AccidentalShotsView: View {
    @State private var vm: AccidentalShotsViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: AccidentalShotsViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if vm.shots.isEmpty {
                    if !vm.isScanning {
                        EmptyState(systemImage: "hand.thumbsup", title: Text("No accidental shots"),
                                   message: Text("No pocket shots, black frames or finger-over-lens photos."))
                    }
                } else {
                    ForEach(vm.sections, id: \.0) { reason, items in
                        section(reason, items)
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .keeprollBackground()
        // New photos taken while Keeproll is open show up after a pull (QA U2).
        .refreshable { vm.rescan() }
        .navigationTitle("Accidental Shots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.allSelected ? "Deselect all" : "Select all") { vm.toggleAll() }
                    .disabled(vm.shots.isEmpty)
            }
        }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalBytes)),
            caption: Text("^[\(vm.shots.count) photo](inflect: true) you probably didn't mean to take"),
            selectedCount: vm.selectedCount,
            hint: HintRow("heart", Text("Favourites are never suggested. Nothing is selected until you choose.")),
            scanning: vm.isScanning && vm.shots.isEmpty ? Text("Checking photos…") : nil
        )
        .animation(Motion.standard, value: vm.totalBytes)
    }

    private func section(_ reason: AccidentalReason, _ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Image(systemName: AccidentalShotsViewModel.symbol(reason))
                    .font(Font.keeproll.headline).foregroundStyle(Color.keeproll.catAccidental).frame(width: 24)
                    .accessibilityHidden(true)
                Text(AccidentalShotsViewModel.title(reason)).font(Font.keeproll.title).foregroundStyle(Color.keeproll.inkPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(items.allSatisfy(vm.isSelected) ? "Deselect" : "Select") { vm.toggleSection(items) }
                    .font(Font.keeproll.caption.weight(.semibold))
                    .foregroundStyle(Color.keeproll.accent)
            }
            Text(AccidentalShotsViewModel.detail(reason))
                .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SelectableMediaGrid(
                items: items,
                isSelected: vm.isSelected,
                setSelected: vm.setSelected,
                accessibilityLabel: { item in
                    Text("\(AccidentalShotsViewModel.title(reason)), \(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""), \(ByteFormatter.string(item.byteSize ?? 0))\(vm.isSelected(item) ? ", selected" : "")")
                }
            )
        }
    }
}
