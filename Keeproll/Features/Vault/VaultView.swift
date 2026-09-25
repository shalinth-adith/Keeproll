import AVKit
import Observation
import PhotosUI
import SwiftUI

/// Private vault (bonus). Locked behind Face ID / passcode; locks again whenever the app
/// leaves the foreground. Adding photos copies them in; the library originals go to Review.
@Observable
final class VaultViewModel {
    enum LockState: Equatable { case locked, unlocking, unlocked, unavailable(String) }

    private(set) var lock: LockState = .locked
    private(set) var items: [VaultItem] = []
    private(set) var importProgress: (done: Int, total: Int)?
    /// Originals just copied in; the banner offers to review removing them.
    private(set) var justCopied = 0
    private(set) var message: String?

    let store: VaultStoring
    private let auth: VaultAuthenticating
    private let cart: CleanupCart
    private let router: AppRouter

    init(store: VaultStoring, auth: VaultAuthenticating, cart: CleanupCart, router: AppRouter) {
        self.store = store
        self.auth = auth
        self.cart = cart
        self.router = router
    }

    var isUnlocked: Bool { lock == .unlocked }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    func unlock() async {
        guard lock != .unlocking, lock != .unlocked else { return }
        lock = .unlocking
        switch await auth.unlock() {
        case .unlocked:
            items = await store.items()
            lock = .unlocked
        case .cancelled:
            lock = .locked
        case .unavailable(let reason):
            lock = .unavailable(reason)
        }
    }

    /// Called when the app leaves the foreground or the screen closes.
    func lockNow() {
        guard lock == .unlocked else { return }
        lock = .locked
        items = []
        justCopied = 0
    }

    func importPicked(_ picked: [PhotosPickerItem]) async {
        let ids = picked.compactMap(\.itemIdentifier)
        guard !ids.isEmpty else {
            if !picked.isEmpty { message = String(localized: "Keeproll needs access to your photos to move them into the vault.") }
            return
        }
        importProgress = (0, ids.count)
        let result = await store.importAssets(ids) { done, total in
            Task { @MainActor in self.importProgress = (done, total) }
        }
        importProgress = nil
        items = await store.items()
        // Copies are safe; the originals are only *suggested* for removal, on Review.
        cart.add(result.copiedAssets.map { CartItem.asset(id: $0.id, category: .vault, bytes: $0.bytes) })
        justCopied = result.copiedAssets.count
        if result.failed > 0 {
            message = String(localized: "\(result.failed) couldn't be copied and stay in your library.")
        }
    }

    func reviewOriginals() {
        justCopied = 0
        router.presentReview()
    }

    func saveToPhotos(_ item: VaultItem) async {
        do {
            try await store.saveToPhotos(item)
            message = String(localized: "Saved a copy to your library.")
        } catch {
            message = String(localized: "Couldn't save to your library.")
        }
    }

    func remove(_ item: VaultItem) async {
        await store.remove([item])
        items = await store.items()
    }

    func clearMessage() { message = nil }
}

struct VaultView: View {
    @State private var vm: VaultViewModel
    @State private var picked: [PhotosPickerItem] = []
    @State private var open: VaultItem?
    @Environment(\.scenePhase) private var scenePhase

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Layout.gridGutter), count: 3)

    init(env: AppEnvironment) {
        _vm = State(initialValue: VaultViewModel(store: env.vault, auth: env.vaultAuth, cart: env.cart, router: env.router))
    }

    var body: some View {
        ZStack {
            Color.keeproll.canvas.ignoresSafeArea()
            switch vm.lock {
            case .unlocked: unlocked
            case .unavailable(let reason):
                EmptyState(systemImage: "lock.slash", title: Text("Vault unavailable"), message: Text(reason))
            case .locked, .unlocking: locked
            }
        }
        // Hide contents in the app switcher, and lock when the app goes to the background.
        .overlay { if scenePhase != .active && vm.isUnlocked { privacyCover } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { vm.lockNow() } }
        .onDisappear { vm.lockNow() }
        .task { await vm.unlock() }
        .navigationTitle("Private Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.isUnlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $picked, maxSelectionCount: 50, matching: .any(of: [.images, .videos]),
                                 photoLibrary: .shared()) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(vm.importProgress != nil)
                }
            }
        }
        .onChange(of: picked) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                await vm.importPicked(newValue)
                picked = []
            }
        }
        .sheet(item: $open) { item in VaultItemView(item: item, vm: vm) }
        .alert(vm.message ?? "", isPresented: Binding(get: { vm.message != nil }, set: { if !$0 { vm.clearMessage() } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var locked: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.keeproll.accent)
                .accessibilityHidden(true)
            Text("Private Vault").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Photos here are kept only on this iPhone, locked with Face ID or your passcode, and out of your photo library.")
                .font(Font.keeproll.body).foregroundStyle(Color.keeproll.inkSecondary).multilineTextAlignment(.center)
            PrimaryButton(title: "Unlock", systemImage: "faceid", isLoading: vm.lock == .unlocking) {
                Task { await vm.unlock() }
            }
        }
        .padding(Spacing.xl)
    }

    private var unlocked: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CategoryHeader(
                    hero: Text("^[\(vm.items.count) item](inflect: true)"),
                    caption: Text("\(ByteFormatter.string(vm.totalBytes)) · only on this iPhone"),
                    hint: HintRow("lock.shield", Text("Locks again when Keeproll goes to the background."))
                )

                if let progress = vm.importProgress {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).tint(Color.keeproll.accent)
                        Text("Copying \(progress.done) of \(progress.total)…").font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                    }
                }

                if vm.justCopied > 0 {
                    InlineBanner(style: .info, systemImage: "checkmark.shield",
                                 message: Text("^[\(vm.justCopied) item](inflect: true) copied into your vault. The originals are still in your library until you remove them on Review.")) {
                        SecondaryButton(title: "Review originals", systemImage: "checklist") { vm.reviewOriginals() }
                    }
                }

                if vm.items.isEmpty && vm.importProgress == nil {
                    EmptyState(systemImage: "lock.shield", title: Text("Your vault is empty"),
                               message: Text("Tap Add to move private photos and videos here."))
                        .padding(.top, Spacing.xxl)
                } else {
                    LazyVGrid(columns: columns, spacing: Layout.gridGutter) {
                        ForEach(vm.items) { item in
                            Button { open = item } label: {
                                VaultThumbnail(url: vm.store.thumbnailURL(for: item))
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        if item.kind == .video {
                                            Image(systemName: "video.fill").font(.caption2).foregroundStyle(.white)
                                                .padding(5).background(.black.opacity(0.5), in: Circle()).padding(5)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(item.kind == .video ? "Vault video" : "Vault photo"))
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
    }

    private var privacyCover: some View {
        ZStack {
            Color.keeproll.canvas.ignoresSafeArea()
            Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(Color.keeproll.accent)
        }
    }
}

/// Loads a vault thumbnail from disk (never through PhotoKit: these aren't in the library).
struct VaultThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Rectangle().fill(Color.keeproll.hairline)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
            .task(id: url) { image = await Self.load(url) }
    }

    @concurrent
    static func load(_ url: URL) async -> UIImage? { UIImage(contentsOfFile: url.path) }
}

/// One vault item: view it, save a copy back to Photos, or remove it from the vault.
struct VaultItemView: View {
    let item: VaultItem
    let vm: VaultViewModel
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if item.kind == .video {
                    VideoPlayer(player: AVPlayer(url: vm.store.fileURL(for: item)))
                } else {
                    VaultThumbnail(url: vm.store.fileURL(for: item))
                        .aspectRatio(contentMode: .fit)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Save to Photos", systemImage: "square.and.arrow.down") {
                        Task { await vm.saveToPhotos(item) }
                    }
                    Spacer()
                    Button("Remove", systemImage: "trash", role: .destructive) { confirmRemove = true }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .confirmationDialog("Remove from vault?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove permanently", role: .destructive) {
                    Task {
                        await vm.remove(item)
                        dismiss()
                    }
                }
            } message: {
                Text("This is the only copy Keeproll keeps. Save it to Photos first if you want to keep it.")
            }
        }
    }
}
