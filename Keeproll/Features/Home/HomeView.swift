import SwiftUI

/// Entry screen after onboarding: brand row, the storage hero on the brand gradient, one
/// primary action, two stat tiles, and a strip of what Keeproll checks (DESIGN_SYSTEM §9).
struct HomeView: View {
    @State private var vm: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: HomeViewModel(scanStore: env.scanStore, router: env.router, settings: env.settings))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                brandRow
                    .padding(.top, Spacing.xs)
                heroCard
                    .rise(0, appeared)
                PrimaryButton(title: primaryTitle, systemImage: vm.hasResults ? "sparkles" : "wand.and.stars") { vm.primaryAction() }
                    .rise(1, appeared)
                if vm.photosLocked { lockedBanner.rise(1, appeared) }
                stats
                    .rise(2, appeared)
                checks
                    .rise(3, appeared)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Home")
        .refreshable { vm.rescan() }
        .onAppear {
            vm.onAppear()
            withAnimation(reduceMotion ? nil : Motion.standard) { appeared = true }
        }
    }

    private var primaryTitle: LocalizedStringKey {
        if vm.isScanning && !vm.hasResults { return "Scanning… see progress" }
        return vm.hasResults ? "See what to clean" : "Scan my iPhone"
    }

    // MARK: Brand row

    private var brandRow: some View {
        HStack(spacing: Spacing.s) {
            KeeprollMarkTile(size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("Keeproll")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.keeproll.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // The tagline can't share the row with the button at accessibility sizes.
                if !typeSize.isAccessibilitySize {
                    Text("Keep what matters")
                        .font(Font.keeproll.caption)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                }
            }
            Spacer(minLength: Spacing.s)
            Button { vm.rescan() } label: {
                Group {
                    if vm.isScanning { ProgressView().controlSize(.small).tint(Color.keeproll.accent) }
                    else { Image(systemName: "arrow.clockwise").font(Font.keeproll.headline).foregroundStyle(Color.keeproll.accent) }
                }
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(Color.keeproll.surface, in: Circle())
                .shadow(color: Elevation.cardColor, radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .disabled(vm.isScanning)
            .accessibilityLabel(Text(vm.isScanning ? "Scanning" : "Rescan"))
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: Spacing.m) {
            StorageRing(snapshot: vm.storage, segments: vm.segments, scanProgress: vm.scanProgress,
                        size: typeSize.isAccessibilitySize ? 150 : 176)
            statusPill
            // The ring shows only a percentage at accessibility sizes, so spell the rest out.
            if typeSize.isAccessibilitySize, let storage = vm.storage {
                Text("\(ByteFormatter.rounded(storage.availableBytes)) free of \(ByteFormatter.rounded(storage.totalBytes))")
                    .font(Font.keeproll.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .padding(.horizontal, Spacing.m)
        .background(KeeprollGradient.hero, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(alignment: .topTrailing) { glowOrb.offset(x: 40, y: -40) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .shadow(color: Color.keeproll.accentDeep.opacity(0.35), radius: Elevation.floatingRadius, y: Elevation.floatingY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibility)
    }

    /// A soft light in the corner so the gradient reads as a surface, not a flat fill.
    private var glowOrb: some View {
        Circle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 180, height: 180)
            .blur(radius: 30)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var statusPill: some View {
        Group {
            if vm.photosLocked {
                Label("Photo access needed", systemImage: "lock.fill")
            } else if let progress = vm.scanProgress {
                Label("Checking photos · \(Int((progress * 100).rounded()))%", systemImage: "sparkles")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else if vm.isScanning {
                Label("Looking for things to clean…", systemImage: "sparkles")
            } else if vm.totalFreeable > 0 {
                Label("Up to \(ByteFormatter.string(vm.totalFreeable)) can be freed", systemImage: "sparkles")
                    .contentTransition(.numericText())
            } else if vm.hasResults {
                Label("All tidy. Nothing to clean right now", systemImage: "checkmark.circle.fill")
            } else {
                Label("Tap Scan to see what can be freed", systemImage: "sparkles")
            }
        }
        .font(Font.keeproll.headline)
        .foregroundStyle(Color.keeproll.accentDeep)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        // A capsule turns into an oval once the text wraps at large sizes.
        .background(Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? Radius.card : 100, style: .continuous))
        .animation(Motion.standard, value: vm.totalFreeable)
    }

    private var heroAccessibility: Text {
        guard let storage = vm.storage else { return Text("Loading storage") }
        let base = "\(ByteFormatter.rounded(storage.availableBytes)) free of \(ByteFormatter.rounded(storage.totalBytes))"
        return vm.totalFreeable > 0 ? Text("\(base). Up to \(ByteFormatter.string(vm.totalFreeable)) can be freed.") : Text(base)
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: Spacing.s) {
            StatTile(symbol: "leaf.fill", tint: Color.keeproll.success, label: Text("Freed so far"),
                     value: Text(vm.settings.lifetimeBytesFreed > 0 ? ByteFormatter.string(vm.settings.lifetimeBytesFreed) : "—"))
            StatTile(symbol: "clock.fill", tint: Color.keeproll.catContacts, label: Text("Last scan"),
                     value: Text(vm.lastScanLabel))
        }
    }

    // MARK: Checks

    private var checks: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("What Keeproll checks")
                .font(Font.keeproll.title)
                .foregroundStyle(Color.keeproll.inkPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: typeSize.isAccessibilitySize ? 1 : 3),
                      spacing: Spacing.s) {
                ForEach(vm.categories) { category in
                    Button { vm.open(category) } label: {
                        VStack(spacing: Spacing.xs) {
                            CategoryTile(category: category, side: 40)
                            Text(category.cardTitle)
                                .font(Font.keeproll.caption.weight(.semibold))
                                .foregroundStyle(Color.keeproll.inkPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(vm.chipValue(for: category) ?? " ")
                                .font(Font.keeproll.badge)
                                .foregroundStyle(Color.keeproll.inkSecondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.s)
                        .card(padding: Spacing.xs)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text("\(Text(category.title))\(vm.chipValue(for: category).map { ", \($0)" } ?? "")"))
                }
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

/// Small metric card: icon, label, value.
struct StatTile: View {
    let symbol: String
    let tint: Color
    let label: Text
    let value: Text

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(Font.keeproll.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                label.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                value.font(Font.keeproll.metric).foregroundStyle(Color.keeproll.inkPrimary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .card(padding: Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// Fade-and-rise entrance, staggered by index. No-op under Reduce Motion.
struct Rise: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 16)
            .animation(Motion.standard.delay(Double(index) * 0.07), value: appeared)
    }
}

extension View {
    func rise(_ index: Int, _ appeared: Bool) -> some View { modifier(Rise(index: index, appeared: appeared)) }
}
