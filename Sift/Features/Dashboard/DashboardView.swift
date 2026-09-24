import SwiftUI

struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    init(env: AppEnvironment) {
        _vm = State(initialValue: DashboardViewModel(scanStore: env.scanStore, router: env.router, settings: env.settings))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                StorageRing(snapshot: vm.storage, segments: vm.segments)
                    .padding(.top, Spacing.s)

                if vm.showLimitedBanner { limitedBanner }
                if vm.showPhotosLocked { lockedBanner }

                LazyVGrid(columns: columns, spacing: Spacing.s) {
                    ForEach(vm.categories) { category in
                        CategoryCard(category: category, state: vm.cardState(for: category)) {
                            vm.open(category)
                        }
                    }
                }

                if vm.settings.lifetimeBytesFreed > 0 {
                    Label("Sift has freed \(ByteFormatter.string(vm.settings.lifetimeBytesFreed)) so far", systemImage: "leaf")
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.sift.canvas)
        .navigationTitle("Sift")
        .refreshable { vm.rescan() }
        .onAppear { vm.onAppear() }
    }

    private var columns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible())]
    }

    private var limitedBanner: some View {
        InlineBanner(
            style: .warning,
            systemImage: "photo.badge.exclamationmark",
            message: Text("Sift can only see the photos you chose. Anything outside that selection won't be scanned.")
        ) {
            HStack(spacing: Spacing.xs) {
                SecondaryButton(title: "Add photos", systemImage: "plus") {
                    Task { await vm.addMorePhotos() }
                }
                SecondaryButton(title: "Allow all") { SystemActions.openSettings() }
            }
        }
    }

    private var lockedBanner: some View {
        InlineBanner(
            style: .warning,
            systemImage: "lock",
            message: Text("Sift needs access to your photos to find what's taking space. Nothing leaves your iPhone.")
        ) {
            SecondaryButton(title: vm.photosPermission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestPhotosAccess() }
            }
        }
    }
}
