import SwiftUI

/// Results-dashboard entry for one category (FR-DASH-2). DESIGN_SYSTEM §8, v4: a soft
/// card with the category's gradient tile, its title, the number in `display` and a
/// caption. State lives in the caption and a small corner badge (lock, check, spinner).
struct CategoryCard: View {
    enum State: Equatable {
        case scanning(progress: Double?)
        case ready(bytes: Int64, count: Int)
        case empty
        case locked
    }

    let category: CleanupCategory
    let state: State
    /// Showing last-known numbers while a new scan runs.
    var refreshing = false
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var tileSide: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    CategoryTile(category: category, side: tileSide)
                    Spacer(minLength: 0)
                    badge
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.cardTitle)
                        .font(Font.keeproll.headline)
                        .foregroundStyle(Color.keeproll.inkPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    number
                    caption
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .opacity(state == .empty ? 0.75 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .locked:
            Image(systemName: "lock.fill")
                .font(Font.keeproll.caption.weight(.bold))
                .foregroundStyle(Color.keeproll.warning)
                .frame(width: 26, height: 26)
                .background(Color.keeproll.warning.opacity(0.14), in: Circle())
        case .empty:
            Image(systemName: "checkmark")
                .font(Font.keeproll.caption.weight(.bold))
                .foregroundStyle(Color.keeproll.success)
                .frame(width: 26, height: 26)
                .background(Color.keeproll.success.opacity(0.14), in: Circle())
        case .scanning:
            ProgressView().controlSize(.small).frame(width: 26, height: 26)
        case .ready:
            if refreshing {
                ProgressView().controlSize(.mini).frame(width: 26, height: 26)
            } else {
                Image(systemName: "chevron.right")
                    .font(Font.keeproll.caption.weight(.bold))
                    .foregroundStyle(Color.keeproll.inkTertiary)
                    .frame(width: 26, height: 26)
            }
        }
    }

    @ViewBuilder private var number: some View {
        switch state {
        case .ready(let bytes, let count):
            Text(hasBytes ? ByteFormatter.string(bytes) : "\(count)")
                .font(Font.keeproll.display)
                .foregroundStyle(Color.keeproll.inkPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
        case .scanning:
            Text("Scanning…")
                .font(Font.keeproll.display)
                .foregroundStyle(Color.keeproll.inkTertiary)
                .lineLimit(1)
        case .empty:
            Text("All clear")
                .font(Font.keeproll.display)
                .foregroundStyle(Color.keeproll.success)
                .lineLimit(1)
        case .locked:
            Text("Locked")
                .font(Font.keeproll.display)
                .foregroundStyle(Color.keeproll.inkTertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var caption: some View {
        Group {
            switch state {
            case .ready(_, let count):
                if hasBytes {
                    Text("^[\(count) item](inflect: true)")
                } else if category == .contacts {
                    Text("^[\(count) duplicate](inflect: true)")
                } else {
                    Text("^[\(count) old event](inflect: true)")
                }
            case .scanning(let progress):
                Text(progress.map { "\(Int(($0 * 100).rounded()))% checked" } ?? String(localized: "Looking…"))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            case .empty:
                Text("Nothing to clean")
            case .locked:
                Text("Tap to allow access")
            }
        }
        .font(Font.keeproll.caption)
        .foregroundStyle(Color.keeproll.inkSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var hasBytes: Bool { category != .contacts && category != .calendar }

    private var accessibilityText: Text {
        switch state {
        case .ready(let bytes, let count):
            hasBytes ? Text("\(Text(category.title)), \(ByteFormatter.string(bytes)), ^[\(count) item](inflect: true)")
                     : Text("\(Text(category.title)), ^[\(count) item](inflect: true)")
        case .scanning: Text("\(Text(category.title)), scanning")
        case .empty: Text("\(Text(category.title)), nothing to clean")
        case .locked: Text("\(Text(category.title)), needs access")
        }
    }
}

/// Full-width card for a tool that isn't a scan category (Swipe, Vault).
struct ToolCard: View {
    let symbol: String
    let tint: Color
    let title: Text
    let subtitle: Text
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var tileSide: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: tileSide * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: tileSide, height: tileSide)
                    .background(KeeprollGradient.tile(tint), in: RoundedRectangle(cornerRadius: tileSide * 0.28, style: .continuous))
                    .shadow(color: tint.opacity(0.28), radius: tileSide * 0.18, y: tileSide * 0.08)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title.font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                    subtitle.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right").font(Font.keeproll.caption.weight(.bold)).foregroundStyle(Color.keeproll.inkTertiary)
            }
            .card()
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.s) {
            CategoryCard(category: .similar, state: .ready(bytes: 1_300_000_000, count: 12)) {}
            CategoryCard(category: .screenshots, state: .scanning(progress: 0.42)) {}
            CategoryCard(category: .videos, state: .empty) {}
            CategoryCard(category: .contacts, state: .locked) {}
        }
        ToolCard(symbol: "hand.draw.fill", tint: Color.keeproll.accent, title: Text("Swipe to sort"),
                 subtitle: Text("Go through suggestions one by one.")) {}
    }
    .padding()
    .background(Color.keeproll.canvas)
}
