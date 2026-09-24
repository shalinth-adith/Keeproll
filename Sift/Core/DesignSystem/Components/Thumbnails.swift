import SwiftUI

/// Loads and shows one asset thumbnail from the injected `ThumbnailProviding`.
struct ThumbnailView: View {
    let id: String
    var pointSize: CGFloat = 120
    /// Single-photo views the user opened may load the sharp copy from their iCloud.
    var allowsNetwork = false
    @Environment(\.thumbnails) private var thumbnails
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var targetSize: CGSize {
        let side = pointSize * displayScale
        return CGSize(width: side, height: side)
    }

    var body: some View {
        // A memory-cached image draws in the first frame, so revisited cells never flash.
        let shown = image ?? thumbnails.cachedThumbnail(for: id, targetSize: targetSize)
        Rectangle()
            .fill(Color.sift.hairline)
            .overlay {
                if let image = shown {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: id) {
                guard thumbnails.cachedThumbnail(for: id, targetSize: targetSize) == nil || allowsNetwork else { return }
                image = await thumbnails.thumbnail(for: id, targetSize: targetSize, allowsNetwork: allowsNetwork)
            }
    }
}

/// A square grid cell with a selection check (FR-SHOT-2).
struct SelectableThumbnail: View {
    let id: String
    let isSelected: Bool
    var caption: String?
    /// Original lives only in iCloud: deleting it frees iCloud space, not iPhone storage.
    var isCloudOnly = false
    let accessibilityText: Text
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ThumbnailView(id: id)
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if isSelected {
                        Color.sift.accent.opacity(0.18)
                        RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous)
                            .strokeBorder(Color.sift.accent, lineWidth: 3)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                    if isCloudOnly { CloudBadge() }
                    if let caption {
                        Text(caption)
                            .font(Font.sift.badge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    }
                    .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.sift.onAccent : .white, isSelected ? Color.sift.accent : .black.opacity(0.25))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .symbolEffect(.bounce, value: isSelected)
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
