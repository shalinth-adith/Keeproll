import Observation
import SwiftUI

/// Live Photos whose clips can go (bonus). Selection here is local: the action is
/// "convert", not "delete". The sheet saves stills, then puts the originals in the
/// cart for Review (D10).
@Observable
final class LivePhotosViewModel {
    private let scanStore: ScanStore
    private let router: AppRouter
    private(set) var selected: Set<String> = []

    init(scanStore: ScanStore, router: AppRouter) {
        self.scanStore = scanStore
        self.router = router
    }

    var candidates: [LivePhotoCandidate] { scanStore.livePhotos.value ?? [] }
    var isLoading: Bool { scanStore.livePhotos.isLoading }
    var totalSaving: Int64 { scanStore.liveBytes }
    var items: [MediaItem] { candidates.map(\.item) }
    var selectedCandidates: [LivePhotoCandidate] { candidates.filter { selected.contains($0.id) } }
    var selectedSaving: Int64 { selectedCandidates.reduce(0) { $0 + $1.videoBytes } }
    var allSelected: Bool { !candidates.isEmpty && selected.count == candidates.count }

    func isSelected(_ item: MediaItem) -> Bool { selected.contains(item.id) }
    func setSelected(_ item: MediaItem, _ on: Bool) { if on { selected.insert(item.id) } else { selected.remove(item.id) } }
    func toggleAll() { selected = allSelected ? [] : Set(candidates.map(\.id)) }
    func clipSize(_ item: MediaItem) -> String? { candidates.first { $0.id == item.id }.map { ByteFormatter.string($0.videoBytes) } }

    func convertSelected() {
        guard !selectedCandidates.isEmpty else { return }
        router.convertLivePhotos(selectedCandidates)
        selected = []
    }
}

struct LivePhotosView: View {
    @State private var vm: LivePhotosViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: LivePhotosViewModel(scanStore: env.scanStore, router: env.router))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                if vm.candidates.isEmpty {
                    if !vm.isLoading {
                        EmptyState(systemImage: "livephoto", title: Text("No Live Photos"),
                                   message: Text("Nothing here with a motion clip to drop."))
                    }
                } else {
                    SelectableMediaGrid(
                        items: vm.items,
                        isSelected: vm.isSelected,
                        setSelected: vm.setSelected,
                        accessibilityLabel: { item in
                            Text("Live Photo, clip \(vm.clipSize(item) ?? ""), \(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")\(vm.isSelected(item) ? ", selected" : "")")
                        },
                        caption: { item in vm.clipSize(item).map { String(localized: "clip \($0)") } }
                    )
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Live Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.allSelected ? "Deselect all" : "Select all") { vm.toggleAll() }
                    .disabled(vm.candidates.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !vm.selectedCandidates.isEmpty {
                PrimaryButton(title: "Convert ^[\(vm.selectedCandidates.count) Live Photo](inflect: true) · save \(ByteFormatter.string(vm.selectedSaving))",
                              systemImage: "livephoto.slash") { vm.convertSelected() }
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: vm.selectedCandidates.isEmpty)
        .overlay { if vm.isLoading && vm.candidates.isEmpty { ProgressView("Looking for Live Photos…") } }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalSaving)),
            caption: Text("^[\(vm.candidates.count) Live Photo](inflect: true) · clips only"),
            selectedCount: vm.selectedCandidates.count,
            hint: HintRow("livephoto", Text("A Live Photo is a still plus a short clip. Converting saves the still with the same date and place; the original then goes to Review."))
        )
        .animation(Motion.standard, value: vm.totalSaving)
    }
}

/// Converts the chosen Live Photos one by one, then sends the originals to Review.
@Observable
final class ConvertLivePhotosViewModel {
    enum Phase: Equatable { case ready, working(done: Int, total: Int), done(converted: Int, failed: Int, saved: Int64), failedAll(String) }

    private(set) var phase: Phase = .ready
    let items: [LivePhotoCandidate]
    private let service: LivePhotoConverting
    private let cart: CleanupCart
    private let scanStore: ScanStore

    init(items: [LivePhotoCandidate], service: LivePhotoConverting, cart: CleanupCart, scanStore: ScanStore) {
        self.items = items
        self.service = service
        self.cart = cart
        self.scanStore = scanStore
    }

    var totalSaving: Int64 { items.reduce(0) { $0 + $1.videoBytes } }
    var isWorking: Bool { if case .working = phase { true } else { false } }

    func convert() async {
        guard !isWorking else { return }
        phase = .working(done: 0, total: items.count)
        scanStore.expectOwnChanges(for: 600) // saving stills posts library changes; not new content
        var converted = 0, failed = 0
        var saved: Int64 = 0
        var lastError: String?
        for (index, candidate) in items.enumerated() {
            do {
                let stillID = try await service.convertToStill(candidate.item)
                // The original is only *suggested* for removal: Review decides (D10).
                cart.add([.asset(id: candidate.id, category: .livePhotos, bytes: candidate.item.byteSize ?? candidate.videoBytes)])
                scanStore.markLivePhotoConverted(original: candidate.id, still: stillID)
                converted += 1
                saved += candidate.videoBytes
            } catch {
                failed += 1
                lastError = error.localizedDescription
            }
            phase = .working(done: index + 1, total: items.count)
        }
        if converted == 0, let lastError { phase = .failedAll(lastError) } else { phase = .done(converted: converted, failed: failed, saved: saved) }
    }
}

struct ConvertLivePhotosSheet: View {
    @State private var vm: ConvertLivePhotosViewModel
    @Environment(\.dismiss) private var dismiss

    init(items: [LivePhotoCandidate], env: AppEnvironment) {
        _vm = State(initialValue: ConvertLivePhotosViewModel(items: items, service: env.livePhotos, cart: env.cart, scanStore: env.scanStore))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: -Spacing.s) {
                    ForEach(vm.items.prefix(4)) { candidate in
                        ThumbnailView(id: candidate.id, pointSize: 120)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous).strokeBorder(Color.keeproll.canvas, lineWidth: 2))
                    }
                    if vm.items.count > 4 {
                        Text("+\(vm.items.count - 4)").font(Font.keeproll.metric).foregroundStyle(Color.keeproll.inkSecondary).padding(.leading, Spacing.l)
                    }
                }
                content
                Spacer()
                footer
            }
            .padding(Spacing.m)
            .background(Color.keeproll.canvas)
            .navigationTitle("Convert to stills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(vm.isWorking) } }
        }
        .interactiveDismissDisabled(vm.isWorking)
    }

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .ready:
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Save about \(ByteFormatter.string(vm.totalSaving))")
                    .font(Font.keeproll.heroNumber).foregroundStyle(Color.keeproll.inkPrimary)
                InlineBanner(style: .info, systemImage: "checkmark.shield",
                             message: Text("Keeproll saves a still copy of each one to your library first, with the same date, place and favourite. The Live Photo originals then go to Review. Nothing is deleted until you confirm."))
            }
        case .working(let done, let total):
            VStack(alignment: .leading, spacing: Spacing.s) {
                ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Color.keeproll.accent)
                Text("Saving stills… \(done) of \(total)").font(Font.keeproll.caption.monospacedDigit()).foregroundStyle(Color.keeproll.inkSecondary)
                Text("Keep Keeproll open until it finishes.").font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkTertiary)
            }
        case .done(let converted, let failed, let saved):
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("^[\(converted) still](inflect: true) saved", systemImage: "checkmark.circle.fill")
                    .font(Font.keeproll.title).foregroundStyle(Color.keeproll.success)
                if failed > 0 {
                    Text("^[\(failed) Live Photo](inflect: true) couldn't be converted and ^[\(failed) was](inflect: true) left unchanged.")
                        .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.warning)
                }
                InlineBanner(style: .info, systemImage: "checklist",
                             message: Text("The originals are in Review. Remove them there to free \(ByteFormatter.string(saved))."))
            }
        case .failedAll(let message):
            InlineBanner(style: .warning, systemImage: "exclamationmark.triangle", message: Text(message))
        }
    }

    @ViewBuilder private var footer: some View {
        switch vm.phase {
        case .ready: PrimaryButton(title: "Convert", systemImage: "livephoto.slash") { Task { await vm.convert() } }
        case .working: PrimaryButton(title: "Converting", isLoading: true) {}
        case .done, .failedAll: PrimaryButton(title: "Done") { dismiss() }
        }
    }
}
