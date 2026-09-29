import Observation
import SwiftUI

/// Screenshots whose content has passed its use-by date (bonus: smart categories).
@Observable
final class ExpiredScreenshotsViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    var entries: [ExpiredScreenshot] { scanStore.expired.value ?? [] }
    var isLoading: Bool { scanStore.expired.isLoading }
    var totalBytes: Int64 { scanStore.expiredBytes }
    var selectedCount: Int { entries.filter { cart.contains(assetID: $0.id) }.count }
    var allSelected: Bool { !entries.isEmpty && entries.allSatisfy { cart.contains(assetID: $0.id) } }

    /// Grouped by kind, in the order the rules are listed.
    var sections: [(ExpiryVerdict.Kind, [ExpiredScreenshot])] {
        let grouped = Dictionary(grouping: entries, by: \.verdict.kind)
        return ExpiryVerdict.Kind.allCases.compactMap { kind in grouped[kind].map { (kind, $0) } }
    }

    func isSelected(_ entry: ExpiredScreenshot) -> Bool { cart.contains(assetID: entry.id) }
    func toggle(_ entry: ExpiredScreenshot) {
        if isSelected(entry) { cart.removeAssets([entry.id]) } else { cart.add([entry.item.cartItem(in: .expired)]) }
    }
    func toggleAll() {
        if allSelected { cart.removeAssets(entries.map(\.id)) } else { cart.add(entries.map { $0.item.cartItem(in: .expired) }) }
    }

    static func title(_ kind: ExpiryVerdict.Kind) -> LocalizedStringResource {
        switch kind {
        case .oneTimeCode: "One-time codes"
        case .boardingPass: "Boarding passes"
        case .ticket: "Tickets"
        case .delivery: "Deliveries"
        case .coupon: "Coupons and offers"
        case .reservation: "Reservations"
        case .parking: "Parking spots"
        }
    }

    static func symbol(_ kind: ExpiryVerdict.Kind) -> String {
        switch kind {
        case .oneTimeCode: "number"
        case .boardingPass: "airplane"
        case .ticket: "ticket"
        case .delivery: "shippingbox"
        case .coupon: "tag"
        case .reservation: "calendar.badge.checkmark"
        case .parking: "parkingsign"
        }
    }

    func detail(_ entry: ExpiredScreenshot) -> String {
        let when = entry.verdict.mentionedDate ?? entry.verdict.expiresAt
        let dated = when.formatted(date: .abbreviated, time: .omitted)
        switch entry.verdict.kind {
        case .oneTimeCode: return String(localized: "Codes stop working within minutes · taken \(dated)")
        case .boardingPass: return String(localized: "Flight was on \(dated)")
        case .ticket: return String(localized: "Event was on \(dated)")
        case .delivery: return String(localized: "Delivered weeks ago · taken \(dated)")
        case .coupon: return String(localized: "Expired \(dated)")
        case .reservation: return String(localized: "Was on \(dated)")
        case .parking: return String(localized: "You've long since driven off · \(dated)")
        }
    }
}

struct ExpiredScreenshotsView: View {
    @State private var vm: ExpiredScreenshotsViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: ExpiredScreenshotsViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                if vm.entries.isEmpty {
                    if !vm.isLoading {
                        EmptyState(systemImage: "clock.badge.checkmark", title: Text("Nothing has expired"),
                                   message: Text("No screenshots of codes, passes or tickets that are past their date."))
                    }
                } else {
                    ForEach(vm.sections, id: \.0) { kind, entries in
                        section(kind, entries)
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Expired Screenshots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.allSelected ? "Deselect all" : "Select all") { vm.toggleAll() }
                    .disabled(vm.entries.isEmpty)
            }
        }
        .overlay { if vm.isLoading && vm.entries.isEmpty { ProgressView("Reading screenshots…") } }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalBytes)),
            caption: Text("^[\(vm.entries.count) screenshot](inflect: true) past their date"),
            selectedCount: vm.selectedCount,
            hint: HintRow("eye.slash", Text("Text is read on this iPhone and never stored. Only the kind and the date are kept."))
        )
        .animation(Motion.standard, value: vm.totalBytes)
    }

    private func section(_ kind: ExpiryVerdict.Kind, _ entries: [ExpiredScreenshot]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: ExpiredScreenshotsViewModel.symbol(kind))
                    .font(Font.keeproll.headline).foregroundStyle(Color.keeproll.catExpired).frame(width: 24)
                Text(ExpiredScreenshotsViewModel.title(kind)).font(Font.keeproll.title).foregroundStyle(Color.keeproll.inkPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("^[\(entries.count) item](inflect: true)").font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                    if index < entries.count - 1 { Divider().overlay(Color.keeproll.hairline).padding(.leading, 72 + Spacing.s) }
                }
            }
            .card(padding: Spacing.s)
        }
    }

    private func row(_ entry: ExpiredScreenshot) -> some View {
        let selected = vm.isSelected(entry)
        return Button { vm.toggle(entry) } label: {
            HStack(spacing: Spacing.s) {
                ThumbnailView(id: entry.id, pointSize: 160)
                    .frame(width: 56, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    .contextMenu {} preview: {
                        ThumbnailView(id: entry.id, pointSize: 600)
                            .aspectRatio(CGFloat(max(entry.item.pixelWidth, 1)) / CGFloat(max(entry.item.pixelHeight, 1)), contentMode: .fit)
                            .frame(idealWidth: 320)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.detail(entry)).font(Font.keeproll.body).foregroundStyle(Color.keeproll.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text("\(ByteFormatter.string(entry.item.byteSize ?? 0)) · \(Int((entry.verdict.confidence * 100).rounded()))% sure")
                        .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(selected ? Color.keeproll.onAccent : Color.keeproll.inkTertiary, selected ? Color.keeproll.accent : .clear)
                    .symbolEffect(.bounce, value: selected)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
