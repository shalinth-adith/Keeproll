import SwiftUI

/// The Home hero ring (DESIGN_SYSTEM §8, `StorageRing`). Drawn on the hero gradient:
/// a translucent white track for free space and a solid white arc for used space, both to
/// scale. What can be freed is one glowing arc at the end of the used space, also to
/// scale: when it is tiny it shows as a dot, never as a fake share of the disk (UX review
/// P1-4). The centre says "free" and "used" in words.
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
                        .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: arc.isFreeable ? .round : .butt))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.isFreeable ? arc.color.opacity(0.8) : .clear, radius: 8)
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

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Free bytes and the used share normally; at accessibility sizes just the free share,
    /// which fits, still with the word "free" (UX review P1-4).
    @ViewBuilder private var centre: some View {
        if let snapshot, typeSize.isAccessibilitySize, snapshot.totalBytes > 0 {
            Text("\(percent(1 - snapshot.usedFraction)) free")
                .font(Font.keeproll.title)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, lineWidth * 2)
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
                Text("\(percent(snapshot.usedFraction)) used")
                    .font(Font.keeproll.badge)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(.horizontal, lineWidth * 1.5)
            .frame(width: size)
        } else {
            ProgressView().tint(.white)
        }
    }

    private struct Arc: Identifiable { let id: String; let start: Double; let end: Double; let color: Color; let isFreeable: Bool }

    /// Used space in white, then what can be freed as one arc at its end. Both to scale.
    private func arcs(for snapshot: StorageSnapshot) -> [Arc] {
        let total = Double(snapshot.totalBytes)
        let used = snapshot.usedFraction
        let freeableBytes = segments.reduce(Int64(0)) { $0 + max($1.bytes, 0) }
        let freeable = min(Double(freeableBytes) / total, used)
        var result = [Arc(id: "used", start: 0, end: used - freeable, color: .white.opacity(0.9), isFreeable: false)]
        if freeableBytes > 0 {
            result.append(Arc(id: "freeable", start: used - freeable, end: used, color: Color.keeproll.warning, isFreeable: true))
        }
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
