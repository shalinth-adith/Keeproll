import Observation
import SwiftUI

/// Videos with dark or blank stretches (bonus: Smart Trim). Each row shows where the dead
/// parts are; Trim saves a copy without them and sends the original to Review. A clip
/// that's dead from start to finish is offered for removal instead.
@Observable
final class SmartTrimViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart
    private let router: AppRouter

    init(scanStore: ScanStore, cart: CleanupCart, router: AppRouter) {
        self.scanStore = scanStore
        self.cart = cart
        self.router = router
    }

    var candidates: [TrimCandidate] { scanStore.visibleTrims }
    var isLoading: Bool { scanStore.trims.isLoading || (scanStore.trims.value == nil && scanStore.isScanning) }
    var totalBytes: Int64 { scanStore.trimBytes }

    func isSelected(_ candidate: TrimCandidate) -> Bool { cart.contains(assetID: candidate.id) }

    /// Only for clips with nothing worth keeping: select the whole original for removal.
    func toggleRemoval(_ candidate: TrimCandidate) {
        if isSelected(candidate) { cart.removeAssets([candidate.id]) } else { cart.add([candidate.item.cartItem(in: .trims)]) }
    }

    func trim(_ candidate: TrimCandidate) { router.trim(candidate) }
    func preview(_ candidate: TrimCandidate) { router.previewVideo(candidate.id) }
}

struct SmartTrimView: View {
    @State private var vm: SmartTrimViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: SmartTrimViewModel(scanStore: env.scanStore, cart: env.cart, router: env.router))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s) {
                CategoryHeader(
                    hero: Text(ByteFormatter.string(vm.totalBytes)),
                    caption: Text("^[\(vm.candidates.count) video](inflect: true) with dark or empty stretches"),
                    hint: HintRow("scissors", Text("A trimmed copy is saved first. The original goes to Review, so nothing is lost until you confirm.")),
                    scanning: vm.isLoading && vm.candidates.isEmpty ? Text("Watching videos for dead stretches…") : nil
                )
                .animation(Motion.standard, value: vm.totalBytes)

                if vm.candidates.isEmpty && !vm.isLoading {
                    EmptyState(systemImage: "scissors", title: Text("Nothing to trim"),
                               message: Text("No videos with long dark or empty stretches."))
                } else {
                    ForEach(vm.candidates) { candidate in
                        TrimRow(candidate: candidate, isSelected: vm.isSelected(candidate),
                                onPreview: { vm.preview(candidate) },
                                onTrim: { vm.trim(candidate) },
                                onToggleRemoval: { vm.toggleRemoval(candidate) })
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Smart Trim")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One candidate: thumbnail, what would be cut, a timeline of the dead stretches, action.
private struct TrimRow: View {
    let candidate: TrimCandidate
    let isSelected: Bool
    let onPreview: () -> Void
    let onTrim: () -> Void
    let onToggleRemoval: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Button(action: onPreview) {
                    ThumbnailView(id: candidate.id, pointSize: 160)
                        .frame(width: 96, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                        .overlay {
                            Image(systemName: "play.fill").font(.caption).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.45), in: Circle())
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Preview video"))
                VStack(alignment: .leading, spacing: 2) {
                    if candidate.isAllDead {
                        Text("Nothing worth keeping").font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                        Text("\(DurationFormatter.string(candidate.duration)) of dark or empty video · \(ByteFormatter.string(candidate.item.byteSize ?? 0))")
                            .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                    } else {
                        Text("\(DurationFormatter.string(candidate.duration)) → \(DurationFormatter.string(candidate.keptSeconds))")
                            .font(Font.keeproll.metric).foregroundStyle(Color.keeproll.inkPrimary)
                        Text("Cuts \(DurationFormatter.string(candidate.deadSeconds)) · saves about \(ByteFormatter.string(candidate.estimatedSaving))")
                            .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            TrimTimeline(candidate: candidate, showsLegend: !candidate.isAllDead)
            if candidate.isAllDead {
                Button(action: onToggleRemoval) {
                    Label(isSelected ? "Selected to remove" : "Select to remove",
                          systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(Font.keeproll.headline)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                        .foregroundStyle(isSelected ? Color.keeproll.onAccent : Color.keeproll.accent)
                        .background(isSelected ? Color.keeproll.accent : Color.keeproll.accentSoft, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .sensoryFeedback(.selection, trigger: isSelected)
            } else {
                Button(action: onTrim) {
                    Label("Trim", systemImage: "scissors")
                        .font(Font.keeproll.headline)
                        .frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
                        .foregroundStyle(Color.keeproll.accent)
                        .background(Color.keeproll.accentSoft, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .card(padding: Spacing.s)
    }
}

/// The clip as a bar: kept stretches solid in the accent, cut stretches as red stripes,
/// with a legend. Shape (solid vs striped) and colour both carry the meaning.
struct TrimTimeline: View {
    let candidate: TrimCandidate
    var showsLegend = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let duration = max(candidate.duration, 0.001)
                ZStack(alignment: .leading) {
                    Color.keeproll.hairline
                    ForEach(candidate.keptRanges, id: \.self) { range in
                        Color.keeproll.accent
                            .frame(width: max(2, width * range.duration / duration))
                            .offset(x: width * range.start / duration)
                    }
                    ForEach(candidate.deadRanges, id: \.self) { range in
                        CutStripes()
                            .frame(width: max(2, width * range.duration / duration))
                            .offset(x: width * range.start / duration)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            if showsLegend {
                HStack(spacing: Spacing.s) {
                    legend(Color.keeproll.accent, Text("Kept \(DurationFormatter.string(candidate.keptSeconds))"), striped: false)
                    legend(Color.keeproll.catTrim, Text("Cut \(DurationFormatter.string(candidate.deadSeconds))"), striped: true)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Cuts \(DurationFormatter.string(candidate.deadSeconds)) of \(DurationFormatter.string(candidate.duration))"))
    }

    private func legend(_ color: Color, _ label: Text, striped: Bool) -> some View {
        HStack(spacing: 4) {
            Group {
                if striped { CutStripes() } else { color }
            }
            .frame(width: 14, height: 8)
            .clipShape(Capsule())
            label.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
        }
    }
}

/// Red diagonal stripes on a pale red base: "this part is cut".
private struct CutStripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.keeproll.catTrim.opacity(0.22)))
            var x = -size.height
            while x < size.width {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(stripe, with: .color(Color.keeproll.catTrim), lineWidth: 2)
                x += 6
            }
        }
    }
}
