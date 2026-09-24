import SwiftUI

/// Loads and shows one asset thumbnail from the injected `ThumbnailProviding`.
struct ThumbnailView: View {
    let id: String
    var pointSize: CGFloat = 120
    @Environment(\.thumbnails) private var thumbnails
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.sift.hairline)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: id) {
                let side = pointSize * displayScale
                image = await thumbnails.thumbnail(for: id, targetSize: CGSize(width: side, height: side))
            }
    }
}

/// A square grid cell with a selection check (FR-SHOT-2).
struct SelectableThumbnail: View {
    let id: String
    let isSelected: Bool
    var caption: String?
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
                    if let caption {
                        Text(caption)
                            .font(Font.sift.badge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
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
