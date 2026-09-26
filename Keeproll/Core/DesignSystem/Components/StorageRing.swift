import SwiftUI

/// The Home hero ring (DESIGN_SYSTEM §8, `StorageRing`). Drawn on the hero gradient:
/// a translucent white track for free space, a solid white arc for used space, and the
/// freeable categories as glowing coloured arcs at the start. Free space sits in the middle.
struct StorageRing: View {
    let snapshot: StorageSnapshot?
    let segments: [StorageSegment]
    /// Photo-scan progress 0…1 while scanning: a thin outer arc sweeps around.
    var scanProgress: Double? = nil
    var size: CGFloat = 176
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var reveal: Double = 0

    private var lineWidth: CGFloat { size * 0.085 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth))
            if let snapshot, snapshot.totalBytes > 0 {
                ForEach(arcs(for: snapshot).reversed(), id: \.id) { arc in
                    Circle()
                        .trim(from: arc.start * reveal, to: arc.end * reveal)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: arc.isCategory ? .round : .butt))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.isCategory ? arc.color.opacity(0.7) : .clear, radius: 8)
                }
            }
            if let scanProgress {
                Circle()
                    .trim(from: 0, to: scanProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-lineWidth * 1.1)
                    .animation(Motion.gentle, value: scanProgress)
            }
            centre
        }
        .frame(width: size, height: size)
        .padding(lineWidth * 1.4)
        .onAppear { withAnimation(reduceMotion ? nil : Motion.gentle.delay(0.15)) { reveal = 1 } }
        .accessibilityHidden(true)
    }

    /// Free bytes normally; at accessibility sizes just the free share, which fits.
    @ViewBuilder private var centre: some View {
        if let snapshot, typeSize.isAccessibilitySize, snapshot.totalBytes > 0 {
            Text(Double(snapshot.availableBytes) / Double(snapshot.totalBytes), format: .percent.precision(.fractionLength(0)))
                .font(Font.keeproll.heroNumber)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, lineWidth * 1.5)
                .frame(width: size)
        } else if let snapshot {
            VStack(spacing: 0) {
                Text(ByteFormatter.rounded(snapshot.availableBytes))
                    .font(Font.keeproll.heroNumber)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text("free of \(ByteFormatter.rounded(snapshot.totalBytes))")
                    .font(Font.keeproll.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, lineWidth * 1.5)
            .frame(width: size)
        } else {
            ProgressView().tint(.white)
        }
    }

    private struct Arc: Identifiable { let id: String; let start: Double; let end: Double; let color: Color; let isCategory: Bool }

    /// Category arcs first (with a visible minimum), then the rest of the used space in white.
    private func arcs(for snapshot: StorageSnapshot) -> [Arc] {
        let total = Double(snapshot.totalBytes)
        var cursor = 0.0
        var result: [Arc] = []
        var categorised: Int64 = 0
        for segment in segments where segment.bytes > 0 {
            let length = max(Double(segment.bytes) / total, 0.025)
            result.append(Arc(id: segment.id, start: cursor, end: cursor + length, color: segment.color, isCategory: true))
            cursor += length
            categorised += segment.bytes
        }
        let other = max(snapshot.usedBytes - categorised, 0)
        result.append(Arc(id: "used", start: cursor, end: min(cursor + Double(other) / total, 1), color: .white.opacity(0.9), isCategory: false))
        return result
    }
}

#Preview {
    ZStack {
        KeeprollGradient.hero.ignoresSafeArea()
        StorageRing(snapshot: StorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 38_200_000_000),
                    segments: [StorageSegment(id: "s", label: "Screenshots", bytes: 6_000_000_000, color: Color.keeproll.catScreenshots),
                               StorageSegment(id: "v", label: "Videos", bytes: 11_000_000_000, color: Color.keeproll.catVideos)],
                    scanProgress: 0.4)
    }
}
