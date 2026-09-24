import SwiftUI

// Design tokens. See docs/DESIGN_SYSTEM.md. Feature views must use these instead of
// literal colours, font sizes or spacing values.

// MARK: - Colour

enum SiftColor {
    static let canvas = Color(.canvas)
    static let surface = Color(.surface)
    static let surfaceRaised = Color(.surfaceRaised)
    static let hairline = Color(.hairline)

    static let inkPrimary = Color(.inkPrimary)
    static let inkSecondary = Color(.inkSecondary)
    static let inkTertiary = Color(.inkTertiary)

    static let accent = Color(.accent)
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
    static let catOther = Color(.catOther)
    static let catFree = Color(.catFree)
}

extension Color {
    /// Namespaced access: `Color.sift.accent`.
    static var sift: SiftColor.Type { SiftColor.self }
}

// MARK: - Typography

enum SiftFont {
    static let heroNumber = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let metric = Font.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()
    static let caption = Font.footnote
    static let badge = Font.caption2.weight(.bold)
}

extension Font {
    static var sift: SiftFont.Type { SiftFont.self }
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
