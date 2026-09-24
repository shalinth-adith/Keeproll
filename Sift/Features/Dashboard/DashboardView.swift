import SwiftUI

struct DashboardView: View {
    @State private var vm: DashboardViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: DashboardViewModel(scanStore: env.scanStore, router: env.router, settings: env.settings))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                StorageHero(snapshot: vm.storage, segments: vm.segments, freeable: vm.totalFreeable, scanProgress: vm.scanProgress)
                    .padding(.top, Spacing.xs)
                    .staggered(0, appeared: appeared)

                if vm.showLimitedBanner { limitedBanner.staggered(1, appeared: appeared) }
                if vm.showPhotosLocked { lockedBanner.staggered(1, appeared: appeared) }

                sectionHeader
                    .staggered(2, appeared: appeared)

                cards

                if vm.showSwipeEntry { swipeEntry.staggered(6, appeared: appeared) }

                #if DEBUG
                Button { vm.openCalibration() } label: {
                    Label("Calibrate thresholds (debug)", systemImage: "gauge.with.dots.needle.33percent")
                        .font(Font.sift.caption.weight(.semibold))
                        .frame(minHeight: Layout.minTouchTarget)
                }
                .foregroundStyle(Color.sift.inkSecondary)
                #endif

                if vm.settings.lifetimeBytesFreed > 0 {
                    Label("Sift has freed \(ByteFormatter.string(vm.settings.lifetimeBytesFreed)) so far", systemImage: "leaf.fill")
                        .font(Font.sift.caption.weight(.semibold))
                        .foregroundStyle(Color.sift.success)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.sift.success.opacity(0.12), in: Capsule())
                        .padding(.top, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.sift.canvas)
        .navigationTitle("Sift")
        .refreshable { vm.rescan() }
        .onAppear {
            vm.onAppear()
            withAnimation(reduceMotion ? nil : Motion.standard) { appeared = true }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Ready to clean")
                .font(Font.sift.title)
                .foregroundStyle(Color.sift.inkPrimary)
            Spacer()
            Button {
                vm.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .font(Font.sift.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.sift.accent)
            .frame(minHeight: Layout.minTouchTarget)
        }
    }

    /// Two cards per row; a lone card takes the full width.
    private var cards: some View {
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: vm.categories.count, by: perRow).map { Array(vm.categories[$0..<min($0 + perRow, vm.categories.count)]) }
        return VStack(spacing: Spacing.s) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: Spacing.s) {
                    ForEach(row) { category in
                        CategoryCard(category: category, state: vm.cardState(for: category), refreshing: vm.isRefreshing(category)) { vm.open(category) }
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .staggered(3 + index, appeared: appeared)
            }
        }
    }

    private var swipeEntry: some View {
        Button { vm.openSwipe() } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: "hand.draw.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.sift.onAccent)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color.sift.accent, Color.sift.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swipe to sort").font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                    Text("Go through suggestions one by one. Right to keep, left to remove.")
                        .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(Font.sift.caption.weight(.bold)).foregroundStyle(Color.sift.inkTertiary)
            }
            .padding(Spacing.m)
            .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
        }
        .buttonStyle(PressableStyle())
    }

    private var limitedBanner: some View {
        InlineBanner(
            style: .warning,
            systemImage: "photo.badge.exclamationmark",
            message: Text("Sift can only see the photos you chose. Anything outside that selection won't be scanned.")
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
            message: Text("Sift needs access to your photos to find what's taking space. Nothing leaves your iPhone.")
        ) {
            SecondaryButton(title: vm.photosPermission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestPhotosAccess() }
            }
        }
    }
}

/// Fade-and-rise entrance, staggered by index. No-op under Reduce Motion.
private struct Staggered: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(Motion.standard.delay(Double(index) * 0.06), value: appeared)
    }
}

private extension View {
    func staggered(_ index: Int, appeared: Bool) -> some View {
        modifier(Staggered(index: index, appeared: appeared))
    }
}
