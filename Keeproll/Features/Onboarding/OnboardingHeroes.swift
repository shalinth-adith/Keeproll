import SwiftUI

/// Illustrated heroes for the three onboarding pages, built from the design system's own
/// tiles and mark so they match the app that follows (DESIGN_SYSTEM §9, Onboarding v4).
enum OnboardingHero {
    /// Brand tile with three category tiles popping in around it.
    struct Welcome: View {
        @State private var shown = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                Circle().fill(Color.keeproll.accent.opacity(0.14)).frame(width: 260, height: 260).blur(radius: 40)
                KeeprollMarkTile(size: 116)
                satellite(.similar, x: -96, y: -52, delay: 0.15)
                satellite(.videos, x: 100, y: -24, delay: 0.25)
                satellite(.contacts, x: -80, y: 68, delay: 0.35)
                satellite(.screenshots, x: 84, y: 76, delay: 0.45)
            }
            .frame(height: 240)
            .onAppear { withAnimation(reduceMotion ? nil : Motion.standard) { shown = true } }
        }

        private func satellite(_ category: CleanupCategory, x: CGFloat, y: CGFloat, delay: Double) -> some View {
            CategoryTile(category: category, side: 44)
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .offset(x: x, y: y)
                .animation(reduceMotion ? nil : Motion.standard.delay(delay), value: shown)
        }
    }

    /// Three near-identical "photos" fanned out, the front one marked Best.
    struct Photos: View {
        @State private var shown = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                Circle().fill(Color.keeproll.catSimilar.opacity(0.14)).frame(width: 240, height: 240).blur(radius: 40)
                photo(rotation: -12, offset: CGSize(width: -44, height: 10), opacity: 0.55, delay: 0.1)
                photo(rotation: 8, offset: CGSize(width: 44, height: 4), opacity: 0.75, delay: 0.2)
                photo(rotation: 0, offset: .zero, opacity: 1, delay: 0.3)
                    .overlay(alignment: .topLeading) { BestBadge().padding(10) }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.keeproll.onAccent, Color.keeproll.accent)
                            .padding(10)
                    }
            }
            .frame(height: 240)
            .onAppear { withAnimation(reduceMotion ? nil : Motion.standard) { shown = true } }
        }

        private func photo(rotation: Double, offset: CGSize, opacity: Double, delay: Double) -> some View {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(LinearGradient(colors: [Color.keeproll.catSimilar.opacity(0.85), Color.keeproll.catVideos.opacity(0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 128, height: 150)
                .overlay(alignment: .bottom) {
                    // A tiny "landscape" so the cards read as photos.
                    Circle().fill(.white.opacity(0.9)).frame(width: 22, height: 22).offset(x: 34, y: -88)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 150)); p.addLine(to: CGPoint(x: 52, y: 70)); p.addLine(to: CGPoint(x: 92, y: 110))
                        p.addLine(to: CGPoint(x: 128, y: 82)); p.addLine(to: CGPoint(x: 128, y: 150)); p.closeSubpath()
                    }
                    .fill(Color.keeproll.accentDeep.opacity(0.85))
                    .frame(width: 128, height: 150)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .rotationEffect(.degrees(shown ? rotation : 0))
                .offset(shown ? offset : .zero)
                .opacity(shown ? opacity : 0)
                .animation(reduceMotion ? nil : Motion.gentle.delay(delay), value: shown)
        }
    }

    /// Two copies of the same person sliding together into one.
    struct Contacts: View {
        @State private var shown = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                Circle().fill(Color.keeproll.catContacts.opacity(0.16)).frame(width: 240, height: 240).blur(radius: 40)
                avatar("PR").offset(x: shown ? -34 : -92)
                avatar("PR").offset(x: shown ? 34 : 92)
                Image(systemName: "arrow.triangle.merge")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.keeproll.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.keeproll.accent, in: Circle())
                    .shadow(color: Color.keeproll.accent.opacity(0.4), radius: 10, y: 4)
                    .offset(y: 62)
                    .scaleEffect(shown ? 1 : 0.4)
                    .opacity(shown ? 1 : 0)
            }
            .frame(height: 240)
            .animation(reduceMotion ? nil : Motion.gentle.delay(0.15), value: shown)
            .onAppear { shown = true }
        }

        private func avatar(_ initials: String) -> some View {
            Text(initials)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.keeproll.catContacts)
                .frame(width: 88, height: 88)
                .background(Color.keeproll.catContacts.opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(Color.keeproll.surface, lineWidth: 4))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        OnboardingHero.Welcome()
        OnboardingHero.Photos()
        OnboardingHero.Contacts()
    }
    .background(Color.keeproll.canvas)
}
