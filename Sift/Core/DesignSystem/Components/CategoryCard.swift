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
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    iconTile
                    Spacer()
                    trailing
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(category.title)
                        .font(Font.sift.headline)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    detail
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .opacity(state == .locked ? 0.85 : 1)
        .accessibilityElement(children: .combine)
    }

    private var iconTile: some View {
        Image(systemName: category.symbol)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: [category.color, category.color.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .shadow(color: category.color.opacity(0.3), radius: 8, y: 4)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .locked:
            Image(systemName: "lock.fill")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.warning)
                .frame(width: 28, height: 28)
                .background(Color.sift.warning.opacity(0.14), in: Circle())
        case .scanning:
            ProgressView().controlSize(.small)
                .frame(width: 28, height: 28)
        default:
            Image(systemName: "chevron.right")
                .font(Font.sift.caption.weight(.bold))
                .foregroundStyle(Color.sift.inkTertiary)
                .frame(width: 28, height: 28)
                .background(Color.sift.canvas, in: Circle())
        }
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .scanning:
            Text("Scanning…")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
        case .ready(let bytes, let count):
            Text(ByteFormatter.string(bytes))
                .font(Font.sift.title.monospacedDigit())
                .foregroundStyle(Color.sift.inkPrimary)
                .contentTransition(.numericText())
            Text("^[\(count) item](inflect: true)")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
        case .empty:
            Label("All clear", systemImage: "checkmark")
                .font(Font.sift.caption.weight(.semibold))
                .foregroundStyle(Color.sift.success)
        case .locked:
            Text("Needs access")
                .font(Font.sift.caption.weight(.semibold))
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
