import SwiftUI

/// Dashboard entry for one category (FR-DASH-2).
struct CategoryCard: View {
    enum State: Equatable {
        case scanning
        case ready(bytes: Int64, count: Int)
        case empty
        case locked
    }

    let category: CleanupCategory
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Image(systemName: category.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(category.color)
                        .frame(width: 36, height: 36)
                        .background(category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    Spacer()
                    Image(systemName: state == .locked ? "lock" : "chevron.right")
                        .font(Font.sift.caption.weight(.semibold))
                        .foregroundStyle(Color.sift.inkTertiary)
                }
                Text(category.title)
                    .font(Font.sift.headline)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .scanning:
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            }
            .font(Font.sift.caption)
            .foregroundStyle(Color.sift.inkSecondary)
        case .ready(let bytes, let count):
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteFormatter.string(bytes))
                    .font(Font.sift.metric)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .contentTransition(.numericText())
                Text("^[\(count) item](inflect: true)")
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkSecondary)
            }
        case .empty:
            Text("All clear")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
        case .locked:
            Text("Needs access")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.warning)
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.s) {
        CategoryCard(category: .screenshots, state: .ready(bytes: 2_100_000_000, count: 834)) {}
        CategoryCard(category: .similar, state: .scanning) {}
        CategoryCard(category: .videos, state: .empty) {}
        CategoryCard(category: .contacts, state: .locked) {}
    }
    .padding()
    .background(Color.sift.canvas)
}
