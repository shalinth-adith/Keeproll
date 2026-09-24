import SwiftUI

/// The Sift brand mark: three stacked cards, the top one lifted and tilted as if being
/// picked out of the pile, with a check in its corner. Same geometry as the app icon
/// (see `scripts/make_app_icon.swift`).
struct SiftMark: View {
    var size: CGFloat = 96
    /// Draw the cards in this colour (white on the icon tile, accent on a plain canvas).
    var ink: Color = .white
    var check: Color = Color.sift.accent

    var body: some View {
        let card = RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
        ZStack {
            card.fill(ink.opacity(0.32))
                .frame(width: size * 0.58, height: size * 0.40)
                .offset(y: size * 0.20)
            card.fill(ink.opacity(0.58))
                .frame(width: size * 0.64, height: size * 0.44)
                .offset(y: size * 0.08)
            card.fill(ink)
                .frame(width: size * 0.70, height: size * 0.48)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.16, weight: .heavy))
                        .foregroundStyle(check)
                        .padding(size * 0.07)
                }
                .rotationEffect(.degrees(-7))
                .offset(x: size * 0.02, y: -size * 0.10)
                .shadow(color: .black.opacity(0.18), radius: size * 0.05, y: size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark on its icon tile, for onboarding and the summary screen.
struct SiftMarkTile: View {
    var size: CGFloat = 96

    var body: some View {
        SiftMark(size: size * 0.9)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color.sift.accent, Color.sift.accent.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            )
            .shadow(color: Color.sift.accent.opacity(0.35), radius: size * 0.2, y: size * 0.08)
    }
}

#Preview {
    HStack(spacing: Spacing.xl) {
        SiftMarkTile(size: 120)
        SiftMark(size: 96, ink: Color.sift.accent, check: .white)
    }
    .padding(Spacing.xxl)
    .background(Color.sift.canvas)
}
