import SwiftUI

/// "Best" pill shown on the kept photo of a similar group.
struct BestBadge: View {
    var body: some View {
        Label("Best", systemImage: "star.fill")
            .font(Font.keeproll.badge)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.keeproll.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.keeproll.accent, in: Capsule())
    }
}

/// Small pill for iCloud-only assets (FR-SIM-7).
struct CloudBadge: View {
    var body: some View {
        Image(systemName: "icloud.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.45), in: Circle())
    }
}

/// Header for one similar-photo group: date · count · freeable, plus a select shortcut.
struct GroupHeader: View {
    let group: SimilarGroup
    let allOthersSelected: Bool
    let onSelectOthers: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(group.date?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: "Unknown date"))
                        .font(Font.keeproll.headline)
                        .foregroundStyle(Color.keeproll.inkPrimary)
                    if group.kind == .exactDuplicate {
                        Text("Exact copies")
                            .font(Font.keeproll.badge)
                            .foregroundStyle(Color.keeproll.catSimilar)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.keeproll.catSimilar.opacity(0.14), in: Capsule())
                    }
                }
                Text("^[\(group.members.count) photo](inflect: true) · \(ByteFormatter.string(group.freeableBytes)) to free")
                    .font(Font.keeproll.caption)
                    .foregroundStyle(Color.keeproll.inkSecondary)
            }
            Spacer()
            Button(allOthersSelected ? "Keep all" : "Keep best only", action: onSelectOthers)
                .font(Font.keeproll.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.keeproll.accent)
                .frame(minHeight: Layout.minTouchTarget)
        }
    }
}

/// A large-videos list row: 16:9 thumbnail with duration, date, size, selection check.
struct VideoRow: View {
    let item: MediaItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void
    /// Estimated saving from compressing this video; nil hides the action.
    var compressSaving: Int64? = nil
    var onCompress: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button(action: onPreview) {
                ThumbnailView(id: item.id, pointSize: 160)
                    .frame(width: 112, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text(DurationFormatter.string(item.duration ?? 0))
                            .font(Font.keeproll.badge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(5)
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.35), in: Circle())
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Preview video"))

            VStack(alignment: .leading, spacing: 3) {
                Text(ByteFormatter.string(item.byteSize ?? 0))
                    .font(Font.keeproll.title.monospacedDigit())
                    .foregroundStyle(Color.keeproll.inkPrimary)
                HStack(spacing: Spacing.xxs) {
                    Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: "Unknown date"))
                    if item.sizeIsEstimated { Text("· approx.") }
                    if item.isCloudOnly { Image(systemName: "icloud") }
                }
                .font(Font.keeproll.caption)
                .foregroundStyle(Color.keeproll.inkSecondary)
                if let compressSaving, let onCompress {
                    Button(action: onCompress) {
                        // Short so it fits on one line next to the thumbnail; the icon says "compress".
                        Label("Save ~\(ByteFormatter.string(compressSaving))", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(Font.keeproll.badge)
                            .foregroundStyle(Color.keeproll.accent)
                            .padding(.horizontal, Spacing.xs).padding(.vertical, 5)
                            .background(Color.keeproll.accentSoft, in: Capsule())
                    }
                    .accessibilityLabel(Text("Compress to save about \(ByteFormatter.string(compressSaving))"))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: Spacing.xs)

            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? Color.keeproll.onAccent : Color.keeproll.inkTertiary,
                                     isSelected ? Color.keeproll.accent : .clear)
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isSelected ? "Deselect" : "Select"))
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.xs)
        .background(isSelected ? Color.keeproll.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(alignment: .bottom) { Divider().overlay(Color.keeproll.hairline) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(Motion.standard, value: isSelected)
    }
}

/// Avatar circle with initials, for contacts without a photo.
struct ContactAvatar: View {
    let contact: ContactSummary
    var size: CGFloat = 40

    var body: some View {
        Text(contact.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.keeproll.catContacts)
            .frame(width: size, height: size)
            .background(Color.keeproll.catContacts.opacity(0.14), in: Circle())
            .overlay {
                if contact.hasImage {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(Color.keeproll.catContacts)
                        .offset(x: size * 0.32, y: size * 0.32)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Media components") {
    VStack(alignment: .leading, spacing: Spacing.l) {
        HStack { BestBadge(); CloudBadge() }
        VideoRow(item: MediaItem(id: "v", kind: .video, creationDate: .now, pixelWidth: 1920, pixelHeight: 1080, duration: 754, isFavorite: false, byteSize: 812_000_000),
                 isSelected: true, onToggle: {}, onPreview: {})
        ContactAvatar(contact: ContactSummary(id: "c", givenName: "Priya", familyName: "Raman", organization: "", phones: [], emails: [], hasImage: true))
    }
    .padding()
    .background(Color.keeproll.canvas)
}
