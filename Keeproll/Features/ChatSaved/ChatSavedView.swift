import Observation
import SwiftUI

/// Images saved from messaging apps, grouped by how sure the engine is (bonus: smart
/// categories). Selecting only adds to the cart; Review still decides (D10).
@Observable
final class ChatSavedViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    var entries: [ChatSavedItem] { scanStore.chats.value ?? [] }
    var isLoading: Bool { scanStore.chats.isLoading }
    var totalBytes: Int64 { scanStore.chatBytes }
    var selectedCount: Int { entries.filter { cart.contains(assetID: $0.id) }.count }

    func entries(at confidence: ChatSavedVerdict.Confidence) -> [ChatSavedItem] { entries.filter { $0.verdict.confidence == confidence } }
    func items(at confidence: ChatSavedVerdict.Confidence) -> [MediaItem] { entries(at: confidence).map(\.item) }

    /// Count of images that look like they came from each app, for the header.
    var sourceSummary: [(ChatSavedVerdict.Source, Int)] {
        let counts = Dictionary(grouping: entries, by: \.verdict.source).mapValues(\.count)
        return [.whatsapp, .telegram, .unknownApp].compactMap { source in counts[source].map { (source, $0) } }
    }

    func isSelected(_ item: MediaItem) -> Bool { cart.contains(assetID: item.id) }
    func setSelected(_ item: MediaItem, _ selected: Bool) {
        if selected { cart.add([item.cartItem(in: .chats)]) } else { cart.removeAssets([item.id]) }
    }

    /// The one-tap shortcut only ever takes the "very likely" tier (D9: explicit, and safe).
    var veryLikelyAllSelected: Bool {
        let tier = items(at: .veryLikely)
        return !tier.isEmpty && tier.allSatisfy { cart.contains(assetID: $0.id) }
    }
    func toggleVeryLikely() {
        let tier = items(at: .veryLikely)
        if veryLikelyAllSelected { cart.removeAssets(tier.map(\.id)) } else { cart.add(tier.map { $0.cartItem(in: .chats) }) }
    }

    func reasonText(_ verdict: ChatSavedVerdict) -> String {
        verdict.reasons.map { reason -> String in
            switch reason {
            case .noCameraData: String(localized: "no camera data")
            case .chatFilename: String(localized: "chat-app file name")
            case .chatDimensions: String(localized: "chat-app size")
            case .noLocation: String(localized: "no location")
            case .jpegOnly: String(localized: "JPEG")
            case .utilityLook: String(localized: "looks like a forward")
            }
        }.joined(separator: " · ")
    }
}

struct ChatSavedView: View {
    @State private var vm: ChatSavedViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: ChatSavedViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if vm.entries.isEmpty {
                    if !vm.isLoading {
                        EmptyState(systemImage: "bubble.left.and.bubble.right", title: Text("Nothing from chats"),
                                   message: Text("Every photo Keeproll checked looks like it was taken on this iPhone."))
                    }
                } else {
                    tier(.veryLikely, title: Text("Very likely"), note: Text("No camera data, and the size or file name of a chat app."))
                    tier(.likely, title: Text("Likely"), note: Text("No camera data plus one more sign."))
                    tier(.possible, title: Text("Possible"), note: Text("Some signs, but it could be an export from an editing app. Check before you select."))
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Saved from Chats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.veryLikelyAllSelected ? "Clear very likely" : "Select very likely") { vm.toggleVeryLikely() }
                    .disabled(vm.items(at: .veryLikely).isEmpty)
            }
        }
        .overlay { if vm.isLoading && vm.entries.isEmpty { ProgressView("Checking where photos came from…") } }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalBytes)),
            caption: caption,
            selectedCount: vm.selectedCount,
            hint: HintRow("camera.metering.none", Text("Photos taken by a camera carry lens and exposure data; forwards from chat apps don't. Favourites are never suggested."))
        )
        .animation(Motion.standard, value: vm.totalBytes)
    }

    private var caption: Text {
        let parts = vm.sourceSummary.map { source, count -> String in
            switch source {
            case .whatsapp: String(localized: "\(count) look like WhatsApp")
            case .telegram: String(localized: "\(count) look like Telegram")
            case .unknownApp: String(localized: "\(count) from other apps")
            }
        }
        return parts.isEmpty ? Text("^[\(vm.entries.count) photo](inflect: true)") : Text(parts.joined(separator: " · "))
    }

    @ViewBuilder private func tier(_ confidence: ChatSavedVerdict.Confidence, title: Text, note: Text) -> some View {
        let entries = vm.entries(at: confidence)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    title.font(Font.keeproll.title).foregroundStyle(Color.keeproll.inkPrimary).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("^[\(entries.count) photo](inflect: true) · \(ByteFormatter.string(entries.reduce(0) { $0 + ($1.item.byteSize ?? 0) }))")
                        .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                }
                note.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary).fixedSize(horizontal: false, vertical: true)
                SelectableMediaGrid(
                    items: entries.map(\.item),
                    isSelected: vm.isSelected,
                    setSelected: vm.setSelected,
                    accessibilityLabel: { item in
                        let entry = entries.first { $0.id == item.id }
                        return Text("Photo from a chat app, \(entry.map { vm.reasonText($0.verdict) } ?? ""), \(ByteFormatter.string(item.byteSize ?? 0))\(vm.isSelected(item) ? ", selected" : "")")
                    }
                )
            }
        }
    }
}
