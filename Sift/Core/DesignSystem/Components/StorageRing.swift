import SwiftUI

struct StorageSegment: Identifiable {
    let id: String
    let label: LocalizedStringResource
    let bytes: Int64
    let color: Color
}

/// Dashboard hero: a ring showing used vs free, with the freeable categories drawn as
/// coloured segments at the start of the used arc, and a legend underneath.
struct StorageHero: View {
    let snapshot: StorageSnapshot?
    let segments: [StorageSegment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    private let lineWidth: CGFloat = 22
    private var freeable: Int64 { segments.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ring
            legend
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.sift.hairline))
        .onAppear { withAnimation(reduceMotion ? nil : Motion.gentle.delay(0.1)) { progress = 1 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.sift.catFree, style: StrokeStyle(lineWidth: lineWidth))
            if let snapshot, snapshot.totalBytes > 0 {
                ForEach(arcs(for: snapshot).reversed(), id: \.segment.id) { arc in
                    Circle()
                        .trim(from: arc.start * progress, to: arc.end * progress)
                        .stroke(arc.segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: arc.isCategory ? .round : .butt))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.isCategory ? arc.segment.color.opacity(0.45) : .clear, radius: 8)
                }
            }
            VStack(spacing: Spacing.xxs) {
                if let snapshot {
                    Text(ByteFormatter.string(snapshot.availableBytes))
                        .font(Font.sift.heroNumber)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text("free of \(ByteFormatter.string(snapshot.totalBytes))")
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                } else {
                    ProgressView()
                }
            }
            .padding(Spacing.xxl)
        }
        .frame(maxWidth: 220)
        .aspectRatio(1, contentMode: .fit)
        .padding(lineWidth / 2)
    }

    private var legend: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.sift.accent)
                Text(freeable > 0
                     ? "Up to \(ByteFormatter.string(freeable)) can be freed"
                     : "Scanning for things to clean…")
                    .font(Font.sift.headline)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .background(Color.sift.accentSoft, in: Capsule())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.s, alignment: .leading)],
                      alignment: .leading, spacing: Spacing.s) {
                LegendItem(color: Color.sift.catFree, label: Text("Free"),
                           value: snapshot.map { ByteFormatter.string($0.availableBytes) })
                LegendItem(color: Color.sift.catOther, label: Text("Used"),
                           value: snapshot.map { ByteFormatter.string($0.usedBytes) })
                ForEach(segments.filter { $0.bytes > 0 }) { segment in
                    LegendItem(color: segment.color, label: Text(segment.label), value: ByteFormatter.string(segment.bytes))
                }
            }
        }
        .animation(Motion.standard, value: freeable)
    }

    private struct LegendItem: View {
        let color: Color
        let label: Text
        let value: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxs) {
                    Circle().fill(color)
                        .overlay(Circle().strokeBorder(Color.sift.inkTertiary.opacity(0.5), lineWidth: 0.5))
                        .frame(width: 8, height: 8)
                    label.font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary).lineLimit(1)
                }
                Text(value ?? "—")
                    .font(Font.sift.metric)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct Arc { let segment: StorageSegment; let start: Double; let end: Double; let isCategory: Bool }

    /// Category segments first, then the rest of the used space as "Used".
    private func arcs(for snapshot: StorageSnapshot) -> [Arc] {
        let total = Double(snapshot.totalBytes)
        var cursor = 0.0
        var result: [Arc] = []
        var categorised: Int64 = 0
        for segment in segments where segment.bytes > 0 {
            // Give tiny categories a visible sliver, so the colour is on the ring.
            let length = max(Double(segment.bytes) / total, 0.012)
            result.append(Arc(segment: segment, start: cursor, end: cursor + length, isCategory: true))
            cursor += length
            categorised += segment.bytes
        }
        let other = max(snapshot.usedBytes - categorised, 0)
        let used = StorageSegment(id: "used", label: "Used", bytes: other, color: Color.sift.catOther)
        result.append(Arc(segment: used, start: cursor, end: min(cursor + Double(other) / total, 1), isCategory: false))
        return result
    }

    private var accessibilityText: Text {
        guard let snapshot else { return Text("Loading storage") }
        let base = "\(ByteFormatter.string(snapshot.availableBytes)) free of \(ByteFormatter.string(snapshot.totalBytes))"
        return freeable > 0 ? Text("\(base). Up to \(ByteFormatter.string(freeable)) can be freed.") : Text(base)
    }
}

#Preview {
    ScrollView {
        StorageHero(
            snapshot: StorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 38_200_000_000),
            segments: [
                StorageSegment(id: "s", label: "Screenshots", bytes: 6_000_000_000, color: Color.sift.catScreenshots),
                StorageSegment(id: "v", label: "Videos", bytes: 11_000_000_000, color: Color.sift.catVideos),
            ]
        )
        .padding()
    }
    .background(Color.sift.canvas)
}
