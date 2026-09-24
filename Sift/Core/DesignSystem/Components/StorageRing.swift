import SwiftUI

struct StorageSegment: Identifiable {
    let id: String
    let label: LocalizedStringResource
    let bytes: Int64
    let color: Color
}

/// Dashboard hero: a ring showing used vs free, with the freeable categories drawn as
/// segments at the start of the used arc.
struct StorageRing: View {
    let snapshot: StorageSnapshot?
    let segments: [StorageSegment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.sift.catFree, style: StrokeStyle(lineWidth: 18))
            if let snapshot, snapshot.totalBytes > 0 {
                ForEach(arcs(for: snapshot), id: \.segment.id) { arc in
                    Circle()
                        .trim(from: arc.start * progress, to: arc.end * progress)
                        .stroke(arc.segment.color, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: Spacing.xxs) {
                if let snapshot {
                    Text(ByteFormatter.string(snapshot.availableBytes))
                        .font(Font.sift.heroNumber)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("free of \(ByteFormatter.string(snapshot.totalBytes))")
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                } else {
                    ProgressView()
                }
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: 240)
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.gentle) { progress = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private struct Arc { let segment: StorageSegment; let start: Double; let end: Double }

    /// Category segments first, then the rest of the used space as "Other".
    private func arcs(for snapshot: StorageSnapshot) -> [Arc] {
        let total = Double(snapshot.totalBytes)
        var cursor = 0.0
        var result: [Arc] = []
        var categorised: Int64 = 0
        for segment in segments where segment.bytes > 0 {
            let length = Double(segment.bytes) / total
            result.append(Arc(segment: segment, start: cursor, end: cursor + length))
            cursor += length
            categorised += segment.bytes
        }
        let other = max(snapshot.usedBytes - categorised, 0)
        let otherSegment = StorageSegment(id: "other", label: "Other", bytes: other, color: Color.sift.catOther)
        result.append(Arc(segment: otherSegment, start: cursor, end: min(cursor + Double(other) / total, 1)))
        return result
    }

    private var accessibilityText: Text {
        guard let snapshot else { return Text("Loading storage") }
        return Text("\(ByteFormatter.string(snapshot.availableBytes)) free of \(ByteFormatter.string(snapshot.totalBytes))")
    }
}

#Preview {
    StorageRing(
        snapshot: StorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 38_200_000_000),
        segments: [StorageSegment(id: "s", label: "Screenshots", bytes: 6_000_000_000, color: Color.sift.catScreenshots)]
    )
    .padding()
    .background(Color.sift.canvas)
}
