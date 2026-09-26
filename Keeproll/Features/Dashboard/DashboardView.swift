import SwiftUI

/// Results (FR-DASH). Reached from Home after a scan: the freeable total with the
/// one-tap "select recommended" action, category cards by kind, and the tools
/// (DESIGN_SYSTEM §9, Dashboard v4).
struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: DashboardViewModel(scanStore: env.scanStore, router: env.router, settings: env.settings, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                summaryCard
                    .padding(.top, Spacing.xs)
                    .rise(0, appeared)

                if vm.showStaleBanner {
                    InlineBanner(style: .info, systemImage: "arrow.clockwise",
                                 message: Text("Your library changed since the last scan.")) {
                        SecondaryButton(title: "Update results", systemImage: "arrow.clockwise") { vm.rescan() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if vm.showLimitedBanner { limitedBanner.rise(1, appeared) }
                if vm.showPhotosLocked { lockedBanner.rise(1, appeared) }

                section(Text("Photos & videos"), index: 2) { grid(vm.photoCategories) }
                if !vm.recordCategories.isEmpty {
                    section(Text("Contacts & calendar"), index: 4) { grid(vm.recordCategories) }
                }
                section(Text("Tools"), index: 6) {
                    VStack(spacing: Spacing.s) {
                        if vm.showSwipeEntry {
                            ToolCard(symbol: "hand.draw.fill", tint: Color.keeproll.accent, title: Text("Swipe to sort"),
                                     subtitle: Text("One photo at a time. Right to keep, left to remove.")) { vm.openSwipe() }
                        }
                        ToolCard(symbol: "lock.shield.fill", tint: Color.keeproll.catVault, title: Text("Private vault"),
                                 subtitle: Text("Keep private photos out of your library, behind Face ID.")) { vm.openVault() }
                    }
                }

                #if DEBUG
                Button { vm.openCalibration() } label: {
                    Label("Calibrate thresholds (debug)", systemImage: "gauge.with.dots.needle.33percent")
                        .font(Font.keeproll.caption)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                }
                .foregroundStyle(Color.keeproll.inkTertiary)
                #endif
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
            .animation(Motion.respecting(reduceMotion, Motion.standard), value: vm.showStaleBanner)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan", systemImage: "arrow.clockwise") { vm.rescan() }
                    .disabled(vm.isScanning)
            }
        }
        .refreshable { vm.rescan() }
        .onAppear {
            vm.onAppear()
            withAnimation(reduceMotion ? nil : Motion.standard) { appeared = true }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(headlineLabel)
                        .font(Font.keeproll.caption.weight(.semibold))
                        .foregroundStyle(Color.keeproll.inkSecondary)
                        .textCase(.uppercase)
                    Group {
                        if vm.showPhotosLocked { Text("Photo access needed") }
                        else if vm.totalFreeable > 0 { Text(ByteFormatter.string(vm.totalFreeable)) }
                        else if vm.isScanning { Text("Scanning…") }
                        else { Text("All tidy") }
                    }
                    .font(Font.keeproll.heroNumber)
                    .foregroundStyle(vm.totalFreeable == 0 && !vm.isScanning && !vm.showPhotosLocked ? Color.keeproll.success : Color.keeproll.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    footnote
                        .font(Font.keeproll.caption)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s)
                if vm.isScanning { ProgressView().controlSize(.regular).tint(Color.keeproll.accent) }
            }
            StorageBar(snapshot: vm.storage, segments: vm.segments)
            if vm.recommendedCount > 0 {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SecondaryButton(title: vm.recommendedAllSelected ? "Clear recommended" : "Select recommended · \(ByteFormatter.string(vm.recommendedBytes))",
                                    systemImage: vm.recommendedAllSelected ? "checkmark.circle.fill" : "wand.and.stars") { vm.toggleRecommended() }
                    HintRow("info.circle", Text("Extra shots from similar groups and blurry photos. Nothing is removed until you confirm on Review."))
                }
                .animation(Motion.standard, value: vm.recommendedAllSelected)
            }
        }
        .card(radius: Radius.sheet, padding: Spacing.l)
        .animation(Motion.standard, value: vm.totalFreeable)
    }

    private var headlineLabel: LocalizedStringKey {
        if vm.showPhotosLocked { return "Nothing scanned" }
        return vm.totalFreeable > 0 || vm.isScanning ? "Up to" : "Result"
    }

    private var footnote: Text {
        var parts: [Text] = []
        if vm.totalFreeable > 0 { parts.append(Text("can be freed")) }
        if let storage = vm.storage {
            parts.append(Text("\(ByteFormatter.rounded(storage.availableBytes)) free of \(ByteFormatter.rounded(storage.totalBytes))"))
        }
        if let progress = vm.scanProgress { parts.append(Text("checking \(Int((progress * 100).rounded()))%")) }
        return parts.dropFirst().reduce(parts.first ?? Text("")) { $0 + Text(" · ") + $1 }
    }

    // MARK: Sections

    private func section<Content: View>(_ title: Text, index: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            title
                .font(Font.keeproll.title)
                .foregroundStyle(Color.keeproll.inkPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .rise(index, appeared)
    }

    /// Two cards per row; a lone card takes the full width; one per row at AX sizes.
    private func grid(_ categories: [CleanupCategory]) -> some View {
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: categories.count, by: perRow).map { Array(categories[$0..<min($0 + perRow, categories.count)]) }
        return VStack(spacing: Spacing.s) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Spacing.s) {
                    ForEach(row) { category in
                        CategoryCard(category: category, state: vm.cardState(for: category), refreshing: vm.isRefreshing(category)) { vm.open(category) }
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var limitedBanner: some View {
        InlineBanner(style: .warning, systemImage: "photo.badge.exclamationmark",
                     message: Text("Keeproll can only see the photos you chose. Anything outside that selection won't be scanned.")) {
            HStack(spacing: Spacing.xs) {
                SecondaryButton(title: "Add photos", systemImage: "plus") { Task { await vm.addMorePhotos() } }
                SecondaryButton(title: "Allow all") { SystemActions.openSettings() }
            }
        }
    }

    private var lockedBanner: some View {
        InlineBanner(style: .warning, systemImage: "lock",
                     message: Text("Keeproll needs access to your photos to find what's taking space. Nothing leaves your iPhone.")) {
            SecondaryButton(title: vm.photosPermission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestPhotosAccess() }
            }
        }
    }
}
