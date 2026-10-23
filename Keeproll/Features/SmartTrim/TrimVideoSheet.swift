import Observation
import SwiftUI

/// Trim one video (bonus: Smart Trim). Flow: explain → trim (progress, cancellable) →
/// the trimmed copy is in the library and the original is in Review. Nothing is removed here.
@Observable
final class TrimVideoViewModel {
    enum Phase: Equatable {
        case ready
        case working(Double)
        case done(TrimResult)
        case failed(String)
    }

    private(set) var phase: Phase = .ready
    private var task: Task<Void, Never>?
    let candidate: TrimCandidate
    private let service: VideoTrimming
    private let cart: CleanupCart
    private let scanStore: ScanStore

    init(candidate: TrimCandidate, service: VideoTrimming, cart: CleanupCart, scanStore: ScanStore) {
        self.candidate = candidate
        self.service = service
        self.cart = cart
        self.scanStore = scanStore
    }

    var isWorking: Bool { if case .working = phase { true } else { false } }
    /// The export is done and the copy is being added to the library. That can't be
    /// interrupted, so Cancel is hidden (QA T3).
    var isSaving: Bool { if case .working(let value) = phase { value >= 0.999 } else { false } }

    func start() {
        guard !isWorking else { return }
        task = Task { await trim() }
    }

    func cancel() {
        guard isWorking, !isSaving else { return }
        task?.cancel()
        task = nil
        phase = .ready
        Log.photos.debug("Trim cancelled by the user")
    }

    func trim() async {
        guard !isWorking else { return }
        phase = .working(0)
        let background = BackgroundActivity.begin("Smart Trim")
        defer { background.end() }
        // Saving the copy posts a library change; it isn't new content to rescan for.
        scanStore.expectOwnChanges(for: 600)
        do {
            let result = try await service.trim(candidate) { value in
                Task { @MainActor in
                    if case .working = self.phase { self.phase = .working(value) }
                }
            }
            // A result means the copy is in the library: always record it, even if the
            // sheet was closed meanwhile, or the original would be orphaned (QA T3).
            // The original is only suggested for removal: it goes to Review (D10), counted
            // at what removing it really frees, since the copy stays (QA T5).
            cart.add([.asset(id: candidate.id, category: .trims, bytes: result.savedBytes)])
            scanStore.markTrimmed(TrimPair(originalID: candidate.id, copyID: result.newAssetID, savedBytes: result.savedBytes,
                                           originalDuration: candidate.duration, keptDuration: candidate.keptSeconds))
            phase = .done(result)
        } catch is CancellationError {
            phase = .ready
        } catch {
            guard !Task.isCancelled else { phase = .ready; return }
            phase = .failed(error.localizedDescription)
        }
    }
}

struct TrimVideoSheet: View {
    @State private var vm: TrimVideoViewModel
    @Environment(\.dismiss) private var dismiss

    init(candidate: TrimCandidate, env: AppEnvironment) {
        _vm = State(initialValue: TrimVideoViewModel(candidate: candidate, service: env.trimmer, cart: env.cart, scanStore: env.scanStore))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: Spacing.m) {
                    ThumbnailView(id: vm.candidate.id, pointSize: 160)
                        .frame(width: 112, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(DurationFormatter.string(vm.candidate.duration)) → \(DurationFormatter.string(vm.candidate.keptSeconds))")
                            .font(Font.keeproll.title.monospacedDigit())
                        Text(ByteFormatter.string(vm.candidate.item.byteSize ?? 0)).font(Font.keeproll.caption)
                            .foregroundStyle(Color.keeproll.inkSecondary)
                    }
                }
                TrimTimeline(candidate: vm.candidate)
                content
                Spacer()
                footer
            }
            .padding(Spacing.m)
            .keeprollBackground()
            .navigationTitle("Smart Trim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else if vm.isWorking {
                        Button("Cancel") { vm.cancel() }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(vm.isWorking)
        .onDisappear { vm.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .ready:
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Save about \(ByteFormatter.string(vm.candidate.estimatedSaving))")
                    .font(Font.keeproll.heroNumber).foregroundStyle(Color.keeproll.inkPrimary)
                InlineBanner(style: .info, systemImage: "checkmark.shield",
                             message: Text("Keeproll saves a copy without the \(DurationFormatter.string(vm.candidate.deadSeconds)) of dark or empty video, at the same quality, date and place. The original then goes to Review. Nothing is deleted until you confirm."))
            }
        case .working(let value):
            VStack(alignment: .leading, spacing: Spacing.s) {
                ProgressView(value: value).tint(Color.keeproll.accent)
                Text(value >= 0.999 ? "Saving the copy…" : "Trimming… \(Int((value * 100).rounded()))%")
                    .font(Font.keeproll.caption.monospacedDigit()).foregroundStyle(Color.keeproll.inkSecondary)
                Text(value >= 0.999 ? "Almost done." : "Tap Cancel to stop. Nothing is saved until it finishes.").font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkTertiary)
            }
        case .done(let result):
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Trimmed copy saved", systemImage: "checkmark.circle.fill")
                    .font(Font.keeproll.title).foregroundStyle(Color.keeproll.success)
                Text("\(ByteFormatter.string(result.originalBytes)) → \(ByteFormatter.string(result.newBytes))")
                    .font(Font.keeproll.metric).foregroundStyle(Color.keeproll.inkPrimary)
                InlineBanner(style: .info, systemImage: "checklist",
                             message: Text("The original is in Review. Remove it there to free \(ByteFormatter.string(result.savedBytes))."))
            }
        case .failed(let message):
            InlineBanner(style: .warning, systemImage: "exclamationmark.triangle", message: Text(message))
        }
    }

    @ViewBuilder private var footer: some View {
        switch vm.phase {
        case .ready:
            PrimaryButton(title: "Save trimmed copy", systemImage: "scissors") { vm.start() }
        case .working:
            PrimaryButton(title: "Trimming", isLoading: true) {}
        case .done, .failed:
            PrimaryButton(title: "Done") { dismiss() }
        }
    }
}
