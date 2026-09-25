import SwiftUI

/// Inline banner for limited access and Recently Deleted notes.
struct InlineBanner<Actions: View>: View {
    enum Style { case info, warning }

    let style: Style
    let systemImage: String
    let message: Text
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(style == .warning ? Color.keeproll.warning : Color.keeproll.accent)
                message
                    .font(Font.keeproll.caption)
                    .foregroundStyle(Color.keeproll.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Color.keeproll.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

extension InlineBanner where Actions == EmptyView {
    init(style: Style, systemImage: String, message: Text) {
        self.init(style: style, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// Full-area message when a list has nothing to show, or access is missing.
struct EmptyState<Action: View>: View {
    let systemImage: String
    let title: Text
    let message: Text
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle, weight: .regular))
                .foregroundStyle(Color.keeproll.inkTertiary)
                .accessibilityHidden(true)
            title
                .font(Font.keeproll.title)
                .foregroundStyle(Color.keeproll.inkPrimary)
            message
                .font(Font.keeproll.body)
                .foregroundStyle(Color.keeproll.inkSecondary)
            action
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Action == EmptyView {
    init(systemImage: String, title: Text, message: Text) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Segmented filter chips (video size, screenshot age).
struct FilterChips<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Text

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        label(option)
                            .font(Font.keeproll.caption.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .frame(minHeight: 36)
                            .foregroundStyle(isSelected ? Color.keeproll.onAccent : Color.keeproll.inkPrimary)
                            .background(isSelected ? Color.keeproll.accent : Color.keeproll.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? .clear : Color.keeproll.hairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Explains why Keeproll needs a permission before the iOS prompt appears (FR-PERM-2/3).
struct PermissionPrimer: View {
    enum Hero { case brandMark, symbol(String) }

    let hero: Hero
    let title: Text
    let reasons: [Text]
    let allowTitle: LocalizedStringKey
    let onAllow: () -> Void
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            heroView
            title
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.keeproll.inkPrimary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(reasons.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.keeproll.accent)
                            .frame(width: 22, height: 22)
                            .background(Color.keeproll.accentSoft, in: Circle())
                            .accessibilityHidden(true)
                        reasons[index]
                            .font(Font.keeproll.body)
                            .foregroundStyle(Color.keeproll.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            VStack(spacing: Spacing.s) {
                PrimaryButton(title: allowTitle, action: onAllow)
                if let onSkip {
                    Button("Not now", action: onSkip)
                        .font(Font.keeproll.headline)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                        .frame(minHeight: Layout.minTouchTarget)
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }

    @ViewBuilder private var heroView: some View {
        switch hero {
        case .brandMark:
            KeeprollMarkTile(size: 112)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.keeproll.accent)
                .frame(width: 112, height: 112)
                .background(Color.keeproll.accentSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
