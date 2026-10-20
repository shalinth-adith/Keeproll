import SwiftUI

struct StorageSegment: Identifiable {
    let id: String
    let label: LocalizedStringResource
    let bytes: Int64
    let color: Color
}

/// The dashboard's one graphic: a 6 pt bar of the device's storage. What can be freed is
/// a coloured segment at the start, the rest of the used space is grey, and free space is
/// the track (DESIGN_SYSTEM §8, `StorageBar`). Everything is to scale; a tiny freeable
/// share shows as a 3 pt sliver, not as a percentage it doesn't have (UX review P1-4).
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
                            .frame(width: max(geo.size.width * part.fraction * progress - 1, part.isFreeable ? 3 * progress : 0))
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

    private struct Part: Identifiable { let id: String; let fraction: Double; let color: Color; var isFreeable = false }

    private func parts(for snapshot: StorageSnapshot) -> [Part] {
        let total = Double(snapshot.totalBytes)
        var result: [Part] = []
        var categorised: Int64 = 0
        for segment in segments where segment.bytes > 0 {
            result.append(Part(id: segment.id, fraction: Double(segment.bytes) / total, color: segment.color, isFreeable: true))
            categorised += segment.bytes
        }
        let other = max(snapshot.usedBytes - categorised, 0)
        result.append(Part(id: "used", fraction: Double(other) / total, color: Color.keeproll.catOther))
        return result
    }
}

#Preview("Storage bar") {
    StorageBar(snapshot: StorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 38_000_000_000),
               segments: [StorageSegment(id: "v", label: "Videos", bytes: 11_000_000_000, color: Color.keeproll.catVideos)])
        .padding()
        .background(Color.keeproll.canvas)
}
