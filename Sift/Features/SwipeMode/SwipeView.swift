import SwiftUI
import Observation

/// Swipe-to-keep-or-delete (bonus B1). Swiping only adds to or removes from the cart;
/// nothing is deleted here (D10).
@Observable
final class SwipeViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart
    private(set) var index = 0
    private(set) var reviewed: [String: Bool] = [:] // id → true if queued for removal

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    /// Suggested photos: every non-best similar shot, then screenshots.
    var deck: [MediaItem] {
        let similar = (scanStore.similar.value ?? []).flatMap(\.othersThanBest)
        let shots = scanStore.screenshots.value ?? []
        var seen = Set<String>()
        return (similar + shots).filter { seen.insert($0.id).inserted }
    }

    var current: MediaItem? { index < deck.count ? deck[index] : nil }
    var next: MediaItem? { index + 1 < deck.count ? deck[index + 1] : nil }
    var isFinished: Bool { !deck.isEmpty && index >= deck.count }
    var removedCount: Int { reviewed.values.filter { $0 }.count }
    var keptCount: Int { reviewed.values.filter { !$0 }.count }
    var queuedBytes: Int64 { deck.filter { reviewed[$0.id] == true }.reduce(0) { $0 + ($1.byteSize ?? 0) } }

    func category(for item: MediaItem) -> CleanupCategory { item.kind == .screenshot ? .screenshots : .similar }

    func keep() {
        guard let current else { return }
        cart.removeAssets([current.id])
        reviewed[current.id] = false
        index += 1
    }

    func remove() {
        guard let current else { return }
        cart.add([current.cartItem(in: category(for: current))])
        reviewed[current.id] = true
        index += 1
    }

    func undo() {
        guard index > 0 else { return }
        index -= 1
        if let item = current {
            cart.removeAssets([item.id])
            reviewed[item.id] = nil
        }
    }
}

struct SwipeView: View {
    @State private var vm: SwipeViewModel
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let threshold: CGFloat = 110

    init(env: AppEnvironment) {
        _vm = State(initialValue: SwipeViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            progress
            ZStack {
                if vm.isFinished {
                    finished
                } else if vm.deck.isEmpty {
                    EmptyState(systemImage: "hand.draw", title: Text("Nothing to sort"), message: Text("Scan first, then swipe through the suggestions."))
                } else {
                    if let next = vm.next { card(next).scaleEffect(0.94).offset(y: 14).opacity(0.7) }
                    if let current = vm.current { activeCard(current) }
                }
            }
            .frame(maxHeight: .infinity)
            if !vm.isFinished && !vm.deck.isEmpty { controls }
        }
        .padding(Spacing.m)
        .background(Color.sift.canvas)
        .navigationTitle("Swipe to sort")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { withAnimation(Motion.standard) { vm.undo() } }
                    .disabled(vm.index == 0)
            }
        }
    }

    private var progress: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Label("\(vm.keptCount) kept", systemImage: "hand.thumbsup")
                Spacer()
                Text(vm.deck.isEmpty ? "" : "\(min(vm.index + 1, vm.deck.count)) of \(vm.deck.count)")
                    .font(Font.sift.metric)
                Spacer()
                Label("\(vm.removedCount) to remove", systemImage: "trash")
            }
            .font(Font.sift.caption)
            .foregroundStyle(Color.sift.inkSecondary)
            ProgressView(value: Double(vm.index), total: Double(max(vm.deck.count, 1)))
                .tint(Color.sift.accent)
        }
    }

    private func card(_ item: MediaItem) -> some View {
        ThumbnailView(id: item.id, pointSize: 500)
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ByteFormatter.string(item.byteSize ?? 0)).font(Font.sift.headline)
                    Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "").font(Font.sift.caption)
                }
                .foregroundStyle(.white)
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }

    private func activeCard(_ item: MediaItem) -> some View {
        let fraction = max(-1, min(1, drag.width / threshold))
        return card(item)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .fill(fraction > 0 ? Color.sift.accent.opacity(0.28 * fraction) : Color.sift.inkTertiary.opacity(0.35 * -fraction))
            }
            .overlay(alignment: fraction > 0 ? .topLeading : .topTrailing) {
                if abs(fraction) > 0.15 {
                    Text(fraction > 0 ? "KEEP" : "REMOVE")
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(fraction > 0 ? Color.sift.accent : Color.sift.inkPrimary)
                        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
                        .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .rotationEffect(.degrees(fraction > 0 ? -12 : 12))
                        .padding(Spacing.l)
                        .opacity(Double(abs(fraction)))
                }
            }
            .offset(drag)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(fraction) * 12))
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if value.translation.width > threshold { fling(.right) }
                        else if value.translation.width < -threshold { fling(.left) }
                        else { withAnimation(Motion.standard) { drag = .zero } }
                    }
            )
            .animation(reduceMotion ? nil : .interactiveSpring(), value: drag)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Photo, \(ByteFormatter.string(item.byteSize ?? 0))"))
            .accessibilityActions {
                Button("Keep") { fling(.right) }
                Button("Remove") { fling(.left) }
            }
    }

    private enum Direction { case left, right }

    private func fling(_ direction: Direction) {
        let outX: CGFloat = direction == .right ? 600 : -600
        withAnimation(reduceMotion ? nil : Motion.standard) { drag = CGSize(width: outX, height: drag.height) }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            if direction == .right { vm.keep() } else { vm.remove() }
            drag = .zero
        }
    }

    private var controls: some View {
        HStack(spacing: Spacing.xl) {
            roundButton("xmark", label: "Remove", tint: Color.sift.inkPrimary, fill: Color.sift.surface) { fling(.left) }
            roundButton("heart.fill", label: "Keep", tint: Color.sift.onAccent, fill: Color.sift.accent) { fling(.right) }
        }
        .padding(.bottom, Spacing.s)
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, tint: Color, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 68, height: 68)
                    .background(fill, in: Circle())
                    .overlay(Circle().strokeBorder(Color.sift.hairline))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                Text(label).font(Font.sift.caption.weight(.semibold)).foregroundStyle(Color.sift.inkSecondary)
            }
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: vm.index)
    }

    private var finished: some View {
        VStack(spacing: Spacing.l) {
            SiftMarkTile(size: 96)
            Text("All sorted")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.sift.inkPrimary)
            Text("^[\(vm.removedCount) photo](inflect: true) queued · \(ByteFormatter.string(vm.queuedBytes)). Nothing is removed until you confirm on Review.")
                .font(Font.sift.body)
                .foregroundStyle(Color.sift.inkSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Back to dashboard") { dismiss() }
        }
        .padding(Spacing.xl)
    }
}
