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
    /// Freeable total with each photo counted once (segments can overlap).
    var freeable: Int64? = nil
    /// Photo-scan progress 0…1 while scanning, nil when idle.
    var scanProgress: Double? = nil
    /// Photos access is missing, so nothing is being looked for (test report F7).
    var photosLocked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var progress: Double = 0

    private let lineWidth: CGFloat = 22
    private var freeableBytes: Int64 { freeable ?? segments.reduce(0) { $0 + $1.bytes } }

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
            if !typeSize.isAccessibilitySize {
                freeSpaceText.padding(Spacing.xxl)
            }
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? 160 : 220)
        .aspectRatio(1, contentMode: .fit)
        .padding(lineWidth / 2)
        .modifier(StackedBelow(active: typeSize.isAccessibilitySize) { freeSpaceText })
    }

    /// "38.2 GB · free of 128 GB". Inside the ring normally; below it at accessibility
    /// text sizes, where it can't fit inside (test report F3).
    private var freeSpaceText: some View {
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
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView()
            }
        }
    }

    private var legend: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: photosLocked ? "lock" : "sparkles")
                    .foregroundStyle(photosLocked ? Color.sift.warning : Color.sift.accent)
                Text(photosLocked
                     ? "Photo access needed to scan"
                     : freeableBytes > 0
                     ? "Up to \(ByteFormatter.string(freeableBytes)) can be freed"
                     : "Looking for things to clean…")
                    .multilineTextAlignment(.center)
                    .font(Font.sift.headline)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
            .padding(.horizontal, typeSize.isAccessibilitySize ? Spacing.m : 0)
            // A capsule turns into an oval once the text wraps at large sizes.
            .background(Color.sift.accentSoft,
                        in: RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? Radius.card : 100, style: .continuous))

            if let scanProgress {
                VStack(spacing: Spacing.xxs) {
                    ProgressView(value: scanProgress).tint(Color.sift.accent)
                    Text("Checking photos · \(Int((scanProgress * 100).rounded()))%")
                        .font(Font.sift.caption.monospacedDigit())
                        .foregroundStyle(Color.sift.inkSecondary)
                        .contentTransition(.numericText())
                }
                .transition(.opacity)
            }

            LazyVGrid(columns: typeSize.isAccessibilitySize
                      ? [GridItem(.flexible(), alignment: .leading)]
                      : [GridItem(.adaptive(minimum: 96), spacing: Spacing.s, alignment: .leading)],
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
        .animation(Motion.standard, value: freeableBytes)
        .animation(Motion.standard, value: scanProgress == nil)
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
                    label.font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
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

    /// Puts `content` in a column under the ring when active.
    private struct StackedBelow<Below: View>: ViewModifier {
        let active: Bool
        @ViewBuilder let below: () -> Below

        func body(content: Content) -> some View {
            if active {
                VStack(spacing: Spacing.m) { content; below() }
            } else {
                content
            }
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
        return freeableBytes > 0 ? Text("\(base). Up to \(ByteFormatter.string(freeableBytes)) can be freed.") : Text(base)
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
