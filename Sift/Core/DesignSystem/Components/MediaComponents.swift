import SwiftUI

/// "Best" pill shown on the kept photo of a similar group.
struct BestBadge: View {
    var body: some View {
        Label("Best", systemImage: "star.fill")
            .font(Font.sift.badge)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.sift.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.sift.accent, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
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
                        .font(Font.sift.headline)
                        .foregroundStyle(Color.sift.inkPrimary)
                    if group.kind == .exactDuplicate {
                        Text("Exact copies")
                            .font(Font.sift.badge)
                            .foregroundStyle(Color.sift.catSimilar)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.sift.catSimilar.opacity(0.14), in: Capsule())
                    }
                }
                Text("^[\(group.members.count) photo](inflect: true) · \(ByteFormatter.string(group.freeableBytes)) to free")
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkSecondary)
            }
            Spacer()
            Button(allOthersSelected ? "Keep all" : "Keep best only", action: onSelectOthers)
                .font(Font.sift.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.sift.accent)
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
                            .font(Font.sift.badge)
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
                    .font(Font.sift.title.monospacedDigit())
                    .foregroundStyle(Color.sift.inkPrimary)
                HStack(spacing: Spacing.xxs) {
                    Text(item.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: "Unknown date"))
                    if item.sizeIsEstimated { Text("· approx.") }
                    if item.isCloudOnly { Image(systemName: "icloud") }
                }
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
                if let compressSaving, let onCompress {
                    Button(action: onCompress) {
                        // Short so it fits on one line next to the thumbnail; the icon says "compress".
                        Label("Save ~\(ByteFormatter.string(compressSaving))", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(Font.sift.badge)
                            .foregroundStyle(Color.sift.accent)
                            .padding(.horizontal, Spacing.xs).padding(.vertical, 5)
                            .background(Color.sift.accentSoft, in: Capsule())
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
                    .foregroundStyle(isSelected ? Color.sift.onAccent : Color.sift.inkTertiary,
                                     isSelected ? Color.sift.accent : .clear)
                    .symbolEffect(.bounce, value: isSelected)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isSelected ? "Deselect" : "Select"))
        }
        .padding(Spacing.s)
        .background(isSelected ? Color.sift.accentSoft : Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(isSelected ? Color.sift.accent : Color.sift.hairline, lineWidth: isSelected ? 1.5 : 1))
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
            .foregroundStyle(Color.sift.catContacts)
            .frame(width: size, height: size)
            .background(Color.sift.catContacts.opacity(0.14), in: Circle())
            .overlay {
                if contact.hasImage {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(Color.sift.catContacts)
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
    .background(Color.sift.canvas)
}
