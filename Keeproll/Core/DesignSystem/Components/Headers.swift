import SwiftUI

/// The header every category screen opens with: the hero number, a caption under it,
/// and a "N selected" chip on the right that appears once the cart has items from
/// this screen (DESIGN_SYSTEM §8, `CategoryHeader`).
struct CategoryHeader: View {
    /// The big number: bytes for media screens, a count for contacts and events.
    let hero: Text
    let caption: Text
    var selectedCount = 0
    /// A one-line tip under the header, shown without a fill (see `HintRow`).
    var hint: HintRow? = nil
    /// Shown while results are still streaming in.
    var scanning: Text? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // The chip sits beside the number, or under the caption once text is large.
            heroRow {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    hero
                        .font(Font.keeproll.heroNumber)
                        .foregroundStyle(Color.keeproll.inkPrimary)
                        .contentTransition(.numericText())
                    caption
                        .font(Font.keeproll.caption)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                }
            } trailing: {
                if selectedCount > 0 {
                    SelectedChip(count: selectedCount)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            if let scanning {
                HStack(spacing: Spacing.xs) {
                    ProgressView().controlSize(.small)
                    scanning
                        .font(Font.keeproll.caption)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                }
                .transition(.opacity)
            }
            if let hint { hint }
        }
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: selectedCount)
        .animation(Motion.standard, value: scanning == nil)
    }

    @ViewBuilder private func heroRow<Leading: View, Trailing: View>(
        @ViewBuilder _ leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) { leading(); trailing() }
        } else {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.s) {
                leading()
                Spacer(minLength: Spacing.s)
                trailing()
            }
        }
    }
}

/// "8 selected" pill in the accent colour.
struct SelectedChip: View {
    let count: Int

    var body: some View {
        Text("\(count) selected")
            .font(Font.keeproll.caption.weight(.semibold))
            .foregroundStyle(Color.keeproll.accent)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(Color.keeproll.accentSoft, in: Capsule())
            .contentTransition(.numericText())
            .accessibilityLabel(Text("\(count) selected for review"))
    }
}

/// A quiet tip: symbol + footnote, no fill. For things that are nice to know.
/// Anything that needs attention (limited access, library changed) uses `InlineBanner`.
struct HintRow: View {
    let systemImage: String
    let message: Text

    init(_ systemImage: String, _ message: Text) {
        self.systemImage = systemImage
        self.message = message
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(Font.keeproll.caption.weight(.semibold))
                .foregroundStyle(Color.keeproll.accent)
                .accessibilityHidden(true)
            message
                .font(Font.keeproll.caption)
                .foregroundStyle(Color.keeproll.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section title with an optional trailing action, used between dashboard groups.
struct SectionHeader<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(Font.keeproll.title)
                .foregroundStyle(Color.keeproll.inkPrimary)
            Spacer()
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: Text) { self.init(title: title) { EmptyView() } }
}

#Preview("Headers") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            CategoryHeader(hero: Text("1.3 GB"), caption: Text("4 groups · 12 photos"), selectedCount: 8,
                           hint: HintRow("star", Text("We picked the sharpest shot in each group as Best. Tap a photo to compare.")),
                           scanning: Text("Still scanning — groups appear as they're found"))
            SectionHeader(Text("Ready to clean"))
        }
        .padding()
    }
    .background(Color.keeproll.canvas)
}
