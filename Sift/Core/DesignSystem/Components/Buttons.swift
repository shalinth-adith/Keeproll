import SwiftUI

/// Full-width capsule button. `role: .destructive` is reserved for the final Review button.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var role: ButtonRole?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Spacing.xs) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Font.sift.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
    }

    private var isDestructive: Bool { role == .destructive }
    private var foreground: Color { isDestructive ? Color.sift.onDestructive : Color.sift.onAccent }
    private var background: Color { isDestructive ? Color.sift.destructive : Color.sift.accent }
}

struct SecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(Font.sift.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Color.sift.accent)
            .background(Color.sift.accentSoft, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Subtle scale on press.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.standard, value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        PrimaryButton(title: "Review", systemImage: "checklist") {}
        PrimaryButton(title: "Delete 42 items", role: .destructive) {}
        PrimaryButton(title: "Deleting", isLoading: true) {}
        SecondaryButton(title: "Add more photos", systemImage: "plus") {}
    }
    .padding()
    .background(Color.sift.canvas)
}
