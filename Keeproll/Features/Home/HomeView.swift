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
                // Locked: the banner's access button is the one action (QA L3).
                if vm.photosLocked {
                    lockedBanner.rise(1, appeared)
                } else {
                    PrimaryButton(title: primaryTitle, systemImage: vm.hasResults ? "sparkles" : "wand.and.stars") { vm.primaryAction() }
                        .rise(1, appeared)
                }
                stats
                    .rise(2, appeared)
                ForecastCard(forecast: vm.forecast, points: vm.forecastPoints)
                    .rise(3, appeared)
                checks
                    .rise(4, appeared)
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
            HStack(spacing: Spacing.xs) {
                roundButton(accessibility: vm.isScanning ? "Scanning" : "Rescan", disabled: vm.isScanning) { vm.rescan() } label: {
                    if vm.isScanning { ProgressView().controlSize(.small).tint(Color.keeproll.accent) }
                    else { Image(systemName: "arrow.clockwise").font(Font.keeproll.headline).foregroundStyle(Color.keeproll.accent) }
                }
                roundButton(accessibility: "Settings") { vm.openSettings() } label: {
                    Image(systemName: "gearshape").font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func roundButton<Label: View>(accessibility: LocalizedStringKey, disabled: Bool = false,
                                          action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(Color.keeproll.surface, in: Circle())
                .shadow(color: Elevation.cardColor, radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
        .accessibilityLabel(Text(accessibility))
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

    /// One card, one row per category: tile, full name, last-known value, chevron. A list
    /// reads correctly wherever the fold falls, which a tile grid did not.
    private var checks: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("What Keeproll checks")
                    .font(Font.keeproll.title)
                    .foregroundStyle(Color.keeproll.inkPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if vm.hasResults {
                    Button("All results") { vm.primaryAction() }
                        .font(Font.keeproll.caption.weight(.semibold))
                        .foregroundStyle(Color.keeproll.accent)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.categories.enumerated()), id: \.element) { index, category in
                    Button { vm.open(category) } label: {
                        HStack(spacing: Spacing.s) {
                            CategoryTile(category: category, side: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category.title)
                                    .font(Font.keeproll.headline)
                                    .foregroundStyle(Color.keeproll.inkPrimary)
                                Text(vm.checkSubtitle(for: category))
                                    .font(Font.keeproll.caption)
                                    .foregroundStyle(Color.keeproll.inkSecondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Spacing.s)
                            if let value = vm.chipValue(for: category) {
                                Text(value)
                                    .font(Font.keeproll.metric)
                                    .foregroundStyle(Color.keeproll.inkPrimary)
                                    .monospacedDigit()
                            }
                            Image(systemName: "chevron.right")
                                .font(Font.keeproll.caption.weight(.bold))
                                .foregroundStyle(Color.keeproll.inkTertiary)
                        }
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    if index < vm.categories.count - 1 {
                        Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s)
                    }
                }
            }
            .card(padding: Spacing.m)
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

/// Where the storage is heading (bonus: forecast). One sentence, one caption, a sparkline
/// of free space over the window. Never alarming: the colour is the accent, and it says
/// "not enough data yet" rather than guessing.
struct ForecastCard: View {
    let forecast: StorageForecast
    let points: [Int64]

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(Font.keeproll.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Storage forecast").font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                headline.font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                caption.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.xs)
            if points.count >= 3 {
                Sparkline(values: points.map(Double.init), tint: tint)
                    .frame(width: 72, height: 32)
                    .accessibilityHidden(true)
            }
        }
        .card(padding: Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch forecast {
        case .notEnoughData: "chart.line.uptrend.xyaxis"
        case .filling: "chart.line.downtrend.xyaxis"
        case .steady: "equal.circle"
        case .freeingUp: "chart.line.uptrend.xyaxis"
        }
    }

    private var tint: Color {
        switch forecast {
        case .filling(_, let days) where days <= 14: Color.keeproll.warning
        case .freeingUp: Color.keeproll.success
        default: Color.keeproll.accent
        }
    }

    private var headline: Text {
        switch forecast {
        case .notEnoughData:
            Text("Learning your pace")
        case .filling(_, let days):
            days == 0 ? Text("Running out of room now")
                : days < 14 ? Text("About ^[\(days) day](inflect: true) until it's full")
                : Text("About ^[\(max(days / 7, 1)) week](inflect: true) until it's full")
        case .steady:
            Text("Holding steady")
        case .freeingUp(let perDay):
            Text("Gaining \(ByteFormatter.string(perDay * 7)) a week")
        }
    }

    private var caption: Text {
        switch forecast {
        case .notEnoughData(let days):
            Text("Open Keeproll on ^[\(StorageForecaster.minimumDays - days) more day](inflect: true) to see where your storage is heading.")
        case .filling(let perDay, _):
            Text("Filling at \(ByteFormatter.string(perDay * 7)) a week. “Full” means under \(ByteFormatter.rounded(StorageForecaster.floorBytes)) free, where iOS starts to struggle.")
        case .steady:
            Text("Free space has barely moved over the last few weeks.")
        case .freeingUp:
            Text("Cleanups are outpacing new photos.")
        }
    }
}

/// A plain line through the values, scaled to the frame. No axes, no dots.
struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let minV = values.min() ?? 0, maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))
            Path { path in
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat((v - minV) / range)))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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
