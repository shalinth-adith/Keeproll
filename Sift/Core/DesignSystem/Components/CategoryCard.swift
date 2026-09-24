import SwiftUI

/// Dashboard entry for one category (FR-DASH-2).
struct CategoryCard: View {
    enum State: Equatable {
        case scanning(progress: Double?)
        case ready(bytes: Int64, count: Int)
        case empty
        case locked
    }

    let category: CleanupCategory
    let state: State
    /// The icon tile grows with Dynamic Type so the glyph never overflows it (F3).
    @ScaledMetric(relativeTo: .title2) private var tileSide: CGFloat = 44
    /// Showing last-known numbers while a new scan runs.
    var refreshing = false
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
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .frame(width: tileSide, height: tileSide)
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
        case .scanning(let progress):
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                ProgressView().controlSize(.small).frame(width: 28, height: 28)
            }
        default:
            if refreshing {
                ProgressView().controlSize(.mini).frame(width: 28, height: 28)
                    .accessibilityLabel(Text("Updating"))
            } else {
            Image(systemName: "chevron.right")
                .font(Font.sift.caption.weight(.bold))
                .foregroundStyle(Color.sift.inkTertiary)
                .frame(width: 28, height: 28)
                .background(Color.sift.canvas, in: Circle())
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch state {
        case .scanning(let progress):
            Text(progress.map { "Scanning… \(Int(($0 * 100).rounded()))%" } ?? String(localized: "Scanning…"))
                .font(Font.sift.caption.monospacedDigit())
                .foregroundStyle(Color.sift.inkSecondary)
                .contentTransition(.numericText())
        case .ready(let bytes, let count):
            if category == .contacts {
                Text("\(count)")
                    .font(Font.sift.title.monospacedDigit())
                    .foregroundStyle(Color.sift.inkPrimary)
                    .contentTransition(.numericText())
                Text("look like duplicates")
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkSecondary)
            } else {
                Text(ByteFormatter.string(bytes))
                    .font(Font.sift.title.monospacedDigit())
                    .foregroundStyle(Color.sift.inkPrimary)
                    .contentTransition(.numericText())
                Text("^[\(count) item](inflect: true)")
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkSecondary)
            }
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
        CategoryCard(category: .similar, state: .scanning(progress: 0.42)) {}
        CategoryCard(category: .videos, state: .empty) {}
        CategoryCard(category: .contacts, state: .locked) {}
    }
    .padding()
    .background(Color.sift.canvas)
}
