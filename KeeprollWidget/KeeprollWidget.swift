import SwiftUI
import WidgetKit

// Home Screen storage widget (bonus B5). Free space is measured live; the freeable and
// lifetime numbers come from the app's last scan via the App Group.

struct StorageEntry: TimelineEntry {
    let date: Date
    let totalBytes: Int64
    let availableBytes: Int64
    let snapshot: WidgetSnapshot

    var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - availableBytes) / Double(totalBytes) : 0
    }

    static let placeholder = StorageEntry(date: .now, totalBytes: 128_000_000_000, availableBytes: 38_000_000_000,
                                          snapshot: WidgetSnapshot(freeableBytes: 2_400_000_000, lifetimeFreedBytes: 0))
}

struct StorageProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func currentEntry() -> StorageEntry {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return StorageEntry(
            date: .now,
            totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0,
            snapshot: WidgetSnapshot.load()
        )
    }
}

private func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .file)
}

struct StorageRingGauge: View {
    let fraction: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color("catFree"), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color("accent"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct KeeprollWidgetView: View {
    let entry: StorageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Keeproll").font(.caption.weight(.bold)).foregroundStyle(Color("accent"))
                Spacer()
            }
            ZStack {
                StorageRingGauge(fraction: entry.usedFraction, lineWidth: 9)
                VStack(spacing: 0) {
                    Text(bytes(entry.availableBytes))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(Color("inkPrimary"))
                    Text("free").font(.caption2).foregroundStyle(Color("inkSecondary"))
                }
                .padding(12)
            }
        }
        .containerBackground(for: .widget) { Color("surface") }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(bytes(entry.availableBytes)) free"))
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ZStack {
                StorageRingGauge(fraction: entry.usedFraction, lineWidth: 11)
                Text("\(Int((entry.usedFraction * 100).rounded()))%")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color("inkPrimary"))
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text("Keeproll").font(.caption.weight(.bold)).foregroundStyle(Color("accent"))
                Text("\(bytes(entry.availableBytes)) free")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color("inkPrimary"))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("of \(bytes(entry.totalBytes))")
                    .font(.caption).foregroundStyle(Color("inkSecondary"))
                if let freeable = entry.snapshot.freeableBytes, freeable > 0 {
                    Label("Up to \(bytes(freeable)) to clean", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("accent"))
                        .lineLimit(1)
                } else {
                    Text("Open Keeproll to scan").font(.caption.weight(.semibold)).foregroundStyle(Color("accent"))
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color("surface") }
    }
}

struct KeeprollStorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeeprollStorage", provider: StorageProvider()) { entry in
            KeeprollWidgetView(entry: entry)
        }
        .configurationDisplayName("Storage")
        .description("Free space on this iPhone, and how much Keeproll can clean.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct KeeprollWidgetBundle: WidgetBundle {
    var body: some Widget { KeeprollStorageWidget() }
}

#Preview(as: .systemMedium) {
    KeeprollStorageWidget()
} timeline: {
    StorageEntry.placeholder
}
