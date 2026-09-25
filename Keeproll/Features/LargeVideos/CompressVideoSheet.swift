import Observation
import SwiftUI

/// Compress one video (bonus). Flow: explain → compress (progress) → the smaller copy
/// is in the library and the original is in Review. Nothing is removed here.
@Observable
final class CompressVideoViewModel {
    enum Phase: Equatable {
        case ready
        case working(Double)
        case done(CompressionResult)
        case failed(String)
    }

    private(set) var phase: Phase = .ready
    let item: MediaItem
    private let service: VideoCompressing
    private let cart: CleanupCart
    private let scanStore: ScanStore

    init(item: MediaItem, service: VideoCompressing, cart: CleanupCart, scanStore: ScanStore) {
        self.item = item
        self.service = service
        self.cart = cart
        self.scanStore = scanStore
    }

    var estimatedSaving: Int64? { VideoCompressionService.worthCompressing(item) }
    var isWorking: Bool { if case .working = phase { true } else { false } }

    func compress() async {
        guard !isWorking else { return }
        phase = .working(0)
        // Saving the copy posts a library change; it isn't new content to rescan for.
        scanStore.expectOwnChanges(for: 600)
        do {
            let result = try await service.compress(item) { value in
                Task { @MainActor in
                    if case .working = self.phase { self.phase = .working(value) }
                }
            }
            // The original is only suggested for removal: it goes to Review, not the bin.
            cart.add([.asset(id: item.id, category: .videos, bytes: result.originalBytes)])
            scanStore.markCompressed(original: item.id, copy: result.newAssetID)
            phase = .done(result)
            scanStore.scan() // show the new copy in the list
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct CompressVideoSheet: View {
    @State private var vm: CompressVideoViewModel
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, env: AppEnvironment) {
        _vm = State(initialValue: CompressVideoViewModel(item: item, service: env.compression, cart: env.cart, scanStore: env.scanStore))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: Spacing.m) {
                    ThumbnailView(id: vm.item.id, pointSize: 160)
                        .frame(width: 112, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ByteFormatter.string(vm.item.byteSize ?? 0)).font(Font.keeproll.title.monospacedDigit())
                        Text(DurationFormatter.string(vm.item.duration ?? 0)).font(Font.keeproll.caption)
                            .foregroundStyle(Color.keeproll.inkSecondary)
                    }
                }
                content
                Spacer()
                footer
            }
            .padding(Spacing.m)
            .background(Color.keeproll.canvas)
            .navigationTitle("Compress video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(vm.isWorking)
                }
            }
        }
        .interactiveDismissDisabled(vm.isWorking)
    }

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .ready:
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let saving = vm.estimatedSaving {
                    Text("Save about \(ByteFormatter.string(saving))")
                        .font(Font.keeproll.heroNumber).foregroundStyle(Color.keeproll.inkPrimary)
                }
                InlineBanner(style: .info, systemImage: "checkmark.shield",
                             message: Text("Keeproll saves a smaller copy (HEVC, up to 1080p) to your library first, with the same date and place. The original then goes to Review. Nothing is deleted until you confirm."))
            }
        case .working(let value):
            VStack(alignment: .leading, spacing: Spacing.s) {
                ProgressView(value: value).tint(Color.keeproll.accent)
                Text("Compressing… \(Int((value * 100).rounded()))%")
                    .font(Font.keeproll.caption.monospacedDigit()).foregroundStyle(Color.keeproll.inkSecondary)
                Text("Keep Keeproll open until it finishes.").font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkTertiary)
            }
        case .done(let result):
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Smaller copy saved", systemImage: "checkmark.circle.fill")
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
            PrimaryButton(title: "Compress", systemImage: "arrow.down.right.and.arrow.up.left") {
                Task { await vm.compress() }
            }
        case .working:
            PrimaryButton(title: "Compressing", isLoading: true) {}
        case .done, .failed:
            PrimaryButton(title: "Done") { dismiss() }
        }
    }
}
