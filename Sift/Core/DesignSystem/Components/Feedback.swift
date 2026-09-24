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
                    .foregroundStyle(style == .warning ? Color.sift.warning : Color.sift.accent)
                message
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Color.sift.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.sift.accent)
            title
                .font(Font.sift.title)
                .foregroundStyle(Color.sift.inkPrimary)
            message
                .font(Font.sift.body)
                .foregroundStyle(Color.sift.inkSecondary)
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
                            .font(Font.sift.caption.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .frame(minHeight: 36)
                            .foregroundStyle(isSelected ? Color.sift.onAccent : Color.sift.inkPrimary)
                            .background(isSelected ? Color.sift.accent : Color.sift.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? .clear : Color.sift.hairline))
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

/// Explains why Sift needs a permission before the iOS prompt appears (FR-PERM-2/3).
struct PermissionPrimer: View {
    let systemImage: String
    let title: Text
    let reasons: [Text]
    let allowTitle: LocalizedStringKey
    let onAllow: () -> Void
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.sift.accent)
                .accessibilityHidden(true)
            title
                .font(Font.sift.title)
                .foregroundStyle(Color.sift.inkPrimary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(reasons.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.sift.accent)
                            .accessibilityHidden(true)
                        reasons[index]
                            .font(Font.sift.body)
                            .foregroundStyle(Color.sift.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
            VStack(spacing: Spacing.s) {
                PrimaryButton(title: allowTitle, action: onAllow)
                if let onSkip {
                    Button("Not now", action: onSkip)
                        .font(Font.sift.headline)
                        .foregroundStyle(Color.sift.inkSecondary)
                        .frame(minHeight: Layout.minTouchTarget)
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
        .background(Color.sift.canvas.ignoresSafeArea())
    }
}
