import SwiftUI

// Design tokens. See docs/DESIGN_SYSTEM.md. Feature views must use these instead of
// literal colours, font sizes or spacing values.

// MARK: - Colour

enum KeeprollColor {
    static let canvas = Color(.canvas)
    static let surface = Color(.surface)
    static let surfaceRaised = Color(.surfaceRaised)
    /// Card background: translucent white, so the mint canvas shows through (frosted).
    static let cardFill = Color(.cardFill)
    /// Thin green edge around cards.
    static let cardStroke = Color(.cardStroke)
    static let hairline = Color(.hairline)

    static let inkPrimary = Color(.inkPrimary)
    static let inkSecondary = Color(.inkSecondary)
    static let inkTertiary = Color(.inkTertiary)

    static let accent = Color(.accent)
    /// Darker teal, the far end of the hero gradient.
    static let accentDeep = Color(.accentDeep)
    static let onAccent = Color(.onAccent)
    static let accentSoft = Color(.accentSoft)
    static let destructive = Color(.destructive)
    static let onDestructive = Color(.onDestructive)
    static let warning = Color(.warning)
    static let success = Color(.success)

    static let catSimilar = Color(.catSimilar)
    static let catScreenshots = Color(.catScreenshots)
    static let catBlurry = Color(.catBlurry)
    static let catVideos = Color(.catVideos)
    static let catContacts = Color(.catContacts)
    static let catCalendar = Color(.catCalendar)
    static let catVault = Color(.catVault)
    static let catChats = Color(.catChats)
    static let catExpired = Color(.catExpired)
    static let catLive = Color(.catLive)
    static let catAccidental = Color(.catAccidental)
    static let catTrim = Color(.catTrim)
    static let catOther = Color(.catOther)
    static let catFree = Color(.catFree)
}

extension Color {
    /// Namespaced access: `Color.keeproll.accent`.
    static var keeproll: KeeprollColor.Type { KeeprollColor.self }
}

// MARK: - Typography

enum KeeprollFont {
    static let heroNumber = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let title = Font.title2.weight(.semibold)
    /// Card and section numbers: the hero's rounded voice at a smaller size.
    static let display = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
    static let headline = Font.headline
    static let body = Font.body
    static let metric = Font.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()
    static let caption = Font.footnote
    static let badge = Font.caption2.weight(.bold)
}

extension Font {
    static var keeproll: KeeprollFont.Type { KeeprollFont.self }
}

// MARK: - Layout

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

enum Radius {
    static let thumb: CGFloat = 8
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 24
}

enum Layout {
    static let minTouchTarget: CGFloat = 44
    static let gridGutter: CGFloat = 2
}

// MARK: - Elevation & surfaces

/// Soft, single-step elevation for cards on the canvas (DESIGN_SYSTEM §5, v4).
enum Elevation {
    /// Green-tinted, so cards float on the mint canvas without a grey halo.
    static let cardColor = Color(.accentDeep).opacity(0.10)
    static let cardRadius: CGFloat = 16
    static let cardY: CGFloat = 6
    static let floatingColor = Color.black.opacity(0.14)
    static let floatingRadius: CGFloat = 24
    static let floatingY: CGFloat = 8
}

/// Shared gradients: the brand hero and a per-category tile gradient.
enum KeeprollGradient {
    static var hero: LinearGradient {
        // Own colours, not accent: in dark mode the accent is a bright mint that made the hero
        // the brightest thing on screen (UX review P3-8). Light mode is unchanged.
        LinearGradient(colors: [Color(.heroTop), Color(.heroBottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func tile(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A surface card with the standard radius and soft shadow. Content screens use this
/// for groups, rows and summaries; the dashboard for category cards.
struct CardStyle: ViewModifier {
    var radius: CGFloat = Radius.card
    var padding: CGFloat? = Spacing.m
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.all, padding ?? 0)
            // Frosted green glass: translucent white over the mint canvas, a thin green edge,
            // and a soft green shadow in light mode. Dark mode separates by edge, not shadow
            // (DESIGN_SYSTEM §5).
            .background(Color.keeproll.cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.keeproll.cardStroke, lineWidth: 1))
            .shadow(color: scheme == .dark ? .clear : Elevation.cardColor, radius: Elevation.cardRadius, y: Elevation.cardY)
    }
}

/// Screen background: the mint canvas with a soft green glow at the top, so the brand
/// colour surrounds the content instead of a flat white page. Frosted cards pick it up.
struct KeeprollBackground: View {
    var body: some View {
        Color.keeproll.canvas
            .overlay(alignment: .top) {
                RadialGradient(colors: [Color.keeproll.accent.opacity(0.20), .clear],
                               center: .top, startRadius: 0, endRadius: 520)
                    .frame(height: 620)
            }
            .ignoresSafeArea()
    }
}

extension View {
    func card(radius: CGFloat = Radius.card, padding: CGFloat? = Spacing.m) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }

    /// The app's screen background (see `KeeprollBackground`).
    func keeprollBackground() -> some View {
        background { KeeprollBackground() }
    }
}

/// Category icon on its gradient tile, at any size. The one visual identity of a category.
struct CategoryTile: View {
    let category: CleanupCategory
    var side: CGFloat = 44

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: side * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(KeeprollGradient.tile(category.color), in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
            .shadow(color: category.color.opacity(0.28), radius: side * 0.18, y: side * 0.08)
            .accessibilityHidden(true)
    }
}

// MARK: - Motion

enum Motion {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let countUp = Animation.easeOut(duration: 1.2)

    /// Returns `animation`, or a plain crossfade when Reduce Motion is on.
    static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}
