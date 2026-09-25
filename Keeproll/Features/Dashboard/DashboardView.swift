import SwiftUI

/// Home (FR-DASH). A plain list on the canvas: headline → storage bar → category
/// rows (empty ones dimmed, at the bottom) → tool rows. No cards, one accent, one
/// graphic (DESIGN_SYSTEM §9).
struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(env: AppEnvironment) {
        _vm = State(initialValue: DashboardViewModel(scanStore: env.scanStore, router: env.router, settings: env.settings))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headline
                    .padding(.top, Spacing.xs)
                StorageBar(snapshot: vm.storage, segments: vm.segments)
                    .padding(.top, Spacing.m)
                    .padding(.bottom, Spacing.xl)

                if vm.showStaleBanner {
                    InlineBanner(style: .info, systemImage: "arrow.clockwise",
                                 message: Text("Your library changed since the last scan.")) {
                        SecondaryButton(title: "Update results", systemImage: "arrow.clockwise") { vm.rescan() }
                    }
                    .padding(.bottom, Spacing.l)
                    .transition(.opacity)
                }
                if vm.showLimitedBanner { limitedBanner.padding(.bottom, Spacing.l) }
                if vm.showPhotosLocked { lockedBanner.padding(.bottom, Spacing.l) }

                categoryRows
                toolRows
                    .padding(.top, Spacing.xl)

                #if DEBUG
                Button { vm.openCalibration() } label: {
                    Label("Calibrate thresholds (debug)", systemImage: "gauge.with.dots.needle.33percent")
                        .font(Font.keeproll.caption)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                }
                .foregroundStyle(Color.keeproll.inkTertiary)
                .padding(.top, Spacing.l)
                #endif
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
            .animation(Motion.respecting(reduceMotion, Motion.standard), value: vm.showStaleBanner)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Keeproll")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan", systemImage: "arrow.clockwise") { vm.rescan() }
                    .disabled(vm.isScanning)
            }
        }
        .refreshable { vm.rescan() }
        .onAppear { vm.onAppear() }
    }

    /// "213 MB can be freed", then the device line; scanning and locked states in words.
    private var headline: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if vm.showPhotosLocked {
                    Text("Photo access needed")
                } else if vm.totalFreeable > 0 {
                    (Text(ByteFormatter.string(vm.totalFreeable)).font(Font.keeproll.heroNumber) + Text(" ")
                     + Text("can be freed").font(Font.keeproll.title.weight(.regular)))
                } else if vm.isScanning {
                    Text("Looking for things to clean…")
                } else {
                    Text("Nothing to clean right now")
                }
            }
            .font(Font.keeproll.title)
            .foregroundStyle(Color.keeproll.inkPrimary)
            .contentTransition(.numericText())
            .animation(Motion.standard, value: vm.totalFreeable)

            // One Text, so it wraps as a sentence at large type sizes.
            footnote
                .font(Font.keeproll.caption)
                .foregroundStyle(Color.keeproll.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var footnote: Text {
        var parts: [Text] = []
        if let storage = vm.storage {
            parts.append(Text("\(ByteFormatter.rounded(storage.availableBytes)) free of \(ByteFormatter.rounded(storage.totalBytes))"))
        }
        if vm.settings.lifetimeBytesFreed > 0 {
            parts.append(Text("\(ByteFormatter.string(vm.settings.lifetimeBytesFreed)) freed so far"))
        }
        if let progress = vm.scanProgress {
            parts.append(Text("checking \(Int((progress * 100).rounded()))%"))
        }
        return parts.dropFirst().reduce(parts.first ?? Text("")) { $0 + Text(" · ") + $1 }
    }

    /// Categories with something to show first; empty ones dimmed at the bottom.
    private var categoryRows: some View {
        let states = vm.categories.map { ($0, vm.cardState(for: $0)) }
        let ordered = states.filter { $0.1 != .empty } + states.filter { $0.1 == .empty }
        return VStack(spacing: 0) {
            Divider().overlay(Color.keeproll.hairline)
            ForEach(ordered, id: \.0) { category, state in
                CategoryRow(category: category, state: state, refreshing: vm.isRefreshing(category)) { vm.open(category) }
                RowDivider()
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: ordered.map(\.0))
    }

    private var toolRows: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.keeproll.hairline)
            if vm.showSwipeEntry {
                ListRow(symbol: "hand.draw", title: Text("Swipe to sort"), action: { vm.openSwipe() }) { EmptyView() }
                RowDivider()
            }
            ListRow(symbol: "lock", title: Text("Private vault"), action: { vm.openVault() }) { EmptyView() }
            RowDivider()
        }
    }

    private var limitedBanner: some View {
        InlineBanner(
            style: .warning,
            systemImage: "photo.badge.exclamationmark",
            message: Text("Keeproll can only see the photos you chose. Anything outside that selection won't be scanned.")
        ) {
            HStack(spacing: Spacing.xs) {
                SecondaryButton(title: "Add photos", systemImage: "plus") { Task { await vm.addMorePhotos() } }
                SecondaryButton(title: "Allow all") { SystemActions.openSettings() }
            }
        }
    }

    private var lockedBanner: some View {
        InlineBanner(
            style: .warning,
            systemImage: "lock",
            message: Text("Keeproll needs access to your photos to find what's taking space. Nothing leaves your iPhone.")
        ) {
            SecondaryButton(title: vm.photosPermission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestPhotosAccess() }
            }
        }
    }
}
