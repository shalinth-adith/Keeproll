import SwiftUI

struct ScreenshotsView: View {
    @State private var vm: ScreenshotsViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: ScreenshotsViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                FilterChips(options: ScreenshotsViewModel.Filter.allCases, selection: $vm.filter) { filter in
                    switch filter {
                    case .all: Text("All")
                    case .olderThan30Days: Text("Older than 30 days")
                    }
                }
                .padding(.horizontal, -Spacing.m)

                if vm.items.isEmpty && !vm.isLoading {
                    EmptyState(
                        systemImage: "camera.viewfinder",
                        title: Text("Nothing to clean here"),
                        message: Text(vm.filter == .all ? "You have no screenshots." : "No screenshots are older than 30 days.")
                    )
                } else {
                    grid
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Screenshots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.allVisibleSelected ? "Deselect all" : "Select all") { vm.toggleSelectAll() }
                    .disabled(vm.items.isEmpty)
            }
        }
        .overlay {
            if vm.isLoading && vm.items.isEmpty { ProgressView() }
        }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalBytes)),
            caption: Text("^[\(vm.items.count) screenshot](inflect: true)"),
            selectedCount: vm.selectedCount,
            hint: HintRow("hand.draw", Text("Drag sideways across photos to select several at once."))
        )
        .animation(Motion.standard, value: vm.totalBytes)
    }

    private var grid: some View {
        SelectableMediaGrid(
            items: vm.items,
            isSelected: vm.isSelected,
            setSelected: vm.setSelected,
            accessibilityLabel: accessibilityText
        )
    }

    private func accessibilityText(for item: MediaItem) -> Text {
        let date = item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: "Unknown date")
        let size = item.byteSize.map(ByteFormatter.string) ?? String(localized: "Unknown size")
        let state = vm.isSelected(item) ? String(localized: "selected") : String(localized: "not selected")
        return Text("Screenshot, \(date), \(size), \(state)")
    }
}
