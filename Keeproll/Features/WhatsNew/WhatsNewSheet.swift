import SwiftUI

/// First launch after an update: what changed, one card, one button.
struct WhatsNewSheet: View {
    let items: [WhatsNewItem]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("What's new")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.keeproll.inkPrimary)
                        Text("Keeproll \(WhatsNew.currentVersion)")
                            .font(Font.keeproll.caption)
                            .foregroundStyle(Color.keeproll.inkSecondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Image(systemName: item.symbol)
                                    .font(Font.keeproll.headline)
                                    .foregroundStyle(Color.keeproll.accent)
                                    .frame(width: 36, height: 36)
                                    .background(Color.keeproll.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                                    Text(item.detail).font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, Spacing.s)
                            if index < items.count - 1 { Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s) }
                        }
                    }
                    .card(padding: Spacing.m)
                }
                .padding(Spacing.m)
            }
            .keeprollBackground()
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Continue", action: onDone)
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.xs)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
