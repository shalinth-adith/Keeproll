import SwiftUI

/// Square thumbnail grid with tap-to-toggle and drag-to-select (FR-SHOT-2).
///
/// Like Photos: a drag that starts sideways selects, a vertical drag scrolls, and a long
/// press still opens the preview. The range from the first cell to the one under the
/// finger takes the opposite of the first cell's state; cells that leave the range go
/// back to how they were.
struct SelectableMediaGrid: View {
    let items: [MediaItem]
    let isSelected: (MediaItem) -> Bool
    let setSelected: (MediaItem, Bool) -> Void
    let accessibilityLabel: (MediaItem) -> Text

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var gridWidth: CGFloat = 0
    @State private var drag: DragState?
    /// Decided on the first few points of a drag: true = selecting, false = scrolling.
    @State private var dragIsSelecting: Bool?

    private struct DragState {
        let startIndex: Int
        let target: Bool
        let original: [String: Bool]
        var currentIndex: Int
    }

    private var columnCount: Int {
        typeSize.isAccessibilitySize ? 2 : (sizeClass == .regular ? 4 : 3)
    }

    private var cellSide: CGFloat {
        let gutters = Layout.gridGutter * CGFloat(columnCount - 1)
        return max((gridWidth - gutters) / CGFloat(columnCount), 1)
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Layout.gridGutter), count: columnCount),
                  spacing: Layout.gridGutter) {
            ForEach(items) { item in
                SelectableThumbnail(
                    id: item.id,
                    isSelected: isSelected(item),
                    caption: item.byteSize.map(ByteFormatter.string),
                    accessibilityText: accessibilityLabel(item)
                ) {
                    setSelected(item, !isSelected(item))
                }
                .contextMenu {
                    Button(isSelected(item) ? "Deselect" : "Select", systemImage: "checkmark.circle") {
                        setSelected(item, !isSelected(item))
                    }
                } preview: {
                    ThumbnailView(id: item.id, pointSize: 400)
                        .aspectRatio(CGFloat(max(item.pixelWidth, 1)) / CGFloat(max(item.pixelHeight, 1)), contentMode: .fit)
                        .frame(idealWidth: 320)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .coordinateSpace(.named("grid"))
        .simultaneousGesture(dragSelect)
        .sensoryFeedback(.impact(weight: .light), trigger: drag?.currentIndex)
    }

    private var dragSelect: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("grid"))
            .onChanged { value in
                if dragIsSelecting == nil {
                    dragIsSelecting = abs(value.translation.width) > abs(value.translation.height)
                }
                guard dragIsSelecting == true, let index = index(at: value.location) else { return }
                if drag == nil, let start = self.index(at: value.startLocation) {
                    let target = !isSelected(items[start])
                    let original = Dictionary(items.map { ($0.id, isSelected($0)) }, uniquingKeysWith: { a, _ in a })
                    drag = DragState(startIndex: start, target: target, original: original, currentIndex: index)
                    apply()
                } else if drag?.currentIndex != index {
                    drag?.currentIndex = index
                    apply()
                }
            }
            .onEnded { _ in
                drag = nil
                dragIsSelecting = nil
            }
    }

    /// Cells in the dragged range take the target state; the rest revert.
    private func apply() {
        guard let drag else { return }
        let range = min(drag.startIndex, drag.currentIndex)...max(drag.startIndex, drag.currentIndex)
        for (index, item) in items.enumerated() {
            let wanted = range.contains(index) ? drag.target : (drag.original[item.id] ?? false)
            if isSelected(item) != wanted { setSelected(item, wanted) }
        }
    }

    private func index(at point: CGPoint) -> Int? {
        guard gridWidth > 0, point.x >= 0, point.y >= 0 else { return nil }
        let stride = cellSide + Layout.gridGutter
        let column = min(Int(point.x / stride), columnCount - 1)
        let row = Int(point.y / stride)
        let index = row * columnCount + column
        return index < items.count ? index : nil
    }
}
