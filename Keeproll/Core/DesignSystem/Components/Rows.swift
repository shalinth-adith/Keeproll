import SwiftUI

/// One-line list row: symbol, title, optional trailing value, chevron. Rows sit
/// directly on the canvas and are separated by hairlines, never wrapped in cards
/// (DESIGN_SYSTEM §5, flat rule).
struct ListRow<Value: View>: View {
    let symbol: String
    var tint: Color = Color.keeproll.inkSecondary
    let title: Text
    /// Dimmed rows are still tappable, but read as "nothing here".
    var dimmed = false
    let action: () -> Void
    @ViewBuilder var value: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            layout {
                Image(systemName: symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(dimmed ? Color.keeproll.inkTertiary : tint)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                title
                    .font(Font.keeproll.body)
                    .foregroundStyle(dimmed ? Color.keeproll.inkTertiary : Color.keeproll.inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Spacing.xs) {
                    value
                        .font(Font.keeproll.metric)
                        .foregroundStyle(dimmed ? Color.keeproll.inkTertiary : Color.keeproll.inkSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(Font.keeproll.caption.weight(.semibold))
                        .foregroundStyle(Color.keeproll.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.s)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// Value moves under the title once text is too large to share a line.
    @ViewBuilder private func layout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs, content: content)
        } else {
            HStack(spacing: Spacing.s, content: content)
        }
    }
}

/// Dashboard row for one cleanup category (FR-DASH-2).
struct CategoryRow: View {
    enum State: Equatable {
        case scanning(progress: Double?)
        case ready(bytes: Int64, count: Int)
        case empty
        case locked
    }

    let category: CleanupCategory
    let state: State
    /// Showing last-known numbers while a new scan runs.
    var refreshing = false
    let action: () -> Void

    var body: some View {
        ListRow(symbol: category.symbol, tint: category.color, title: Text(category.title), dimmed: state == .empty, action: action) {
            switch state {
            case .ready(let bytes, let count):
                HStack(spacing: Spacing.xs) {
                    if refreshing { ProgressView().controlSize(.mini) }
                    Text(hasBytes ? ByteFormatter.string(bytes) : "\(count)")
                        .contentTransition(.numericText())
                }
            case .scanning:
                ProgressView().controlSize(.small)
            case .empty:
                Text("None")
            case .locked:
                Text("Allow access")
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    /// Contacts and events have no byte size; their value is a count.
    private var hasBytes: Bool { category != .contacts && category != .calendar }

    private var accessibilityText: Text {
        switch state {
        case .ready(let bytes, let count):
            hasBytes ? Text("\(Text(category.title)), \(ByteFormatter.string(bytes)), ^[\(count) item](inflect: true)")
                     : Text("\(Text(category.title)), ^[\(count) item](inflect: true)")
        case .scanning: Text("\(Text(category.title)), scanning")
        case .empty: Text("\(Text(category.title)), nothing to clean")
        case .locked: Text("\(Text(category.title)), needs access")
        }
    }
}

/// Hairline between rows, inset to the text edge.
struct RowDivider: View {
    var body: some View {
        Divider().overlay(Color.keeproll.hairline).padding(.leading, 28 + Spacing.s)
    }
}

struct StorageSegment: Identifiable {
    let id: String
    let label: LocalizedStringResource
    let bytes: Int64
    let color: Color
}

/// The dashboard's one graphic: a 6 pt bar of the device's storage. Freeable
/// categories are coloured segments at the start, the rest of the used space is
/// grey, and free space is the track (DESIGN_SYSTEM §8, `StorageBar`).
struct StorageBar: View {
    let snapshot: StorageSnapshot?
    let segments: [StorageSegment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if let snapshot, snapshot.totalBytes > 0 {
                    ForEach(parts(for: snapshot)) { part in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(part.color)
                            .frame(width: max(geo.size.width * part.fraction * progress - 1, 0))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .background(Color.keeproll.catFree, in: Capsule())
        .clipShape(Capsule())
        .onAppear { withAnimation(reduceMotion ? nil : Motion.gentle) { progress = 1 } }
        .accessibilityHidden(true)
    }

    private struct Part: Identifiable { let id: String; let fraction: Double; let color: Color }

    private func parts(for snapshot: StorageSnapshot) -> [Part] {
        let total = Double(snapshot.totalBytes)
        var result: [Part] = []
        var categorised: Int64 = 0
        for segment in segments where segment.bytes > 0 {
            // Tiny categories still get a visible sliver, so the colour appears on the bar.
            result.append(Part(id: segment.id, fraction: max(Double(segment.bytes) / total, 0.015), color: segment.color))
            categorised += segment.bytes
        }
        let other = max(snapshot.usedBytes - categorised, 0)
        result.append(Part(id: "used", fraction: Double(other) / total, color: Color.keeproll.catOther))
        return result
    }
}

#Preview("Rows") {
    VStack(spacing: 0) {
        StorageBar(snapshot: StorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 38_000_000_000),
                   segments: [StorageSegment(id: "v", label: "Videos", bytes: 11_000_000_000, color: Color.keeproll.catVideos)])
            .padding(.bottom, Spacing.l)
        CategoryRow(category: .similar, state: .ready(bytes: 1_300_000_000, count: 12)) {}
        RowDivider()
        CategoryRow(category: .videos, state: .scanning(progress: nil)) {}
        RowDivider()
        CategoryRow(category: .contacts, state: .locked) {}
        RowDivider()
        CategoryRow(category: .screenshots, state: .empty) {}
        RowDivider()
        ListRow(symbol: "hand.draw", title: Text("Swipe to sort"), action: {}) { EmptyView() }
    }
    .padding()
    .background(Color.keeproll.canvas)
}
