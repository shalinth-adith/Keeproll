import SwiftUI

/// Sticky bottom bar shown whenever the cart has items (FR-DASH-4).
struct SelectionBar: View {
    let cart: CleanupCart
    let onReview: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !cart.isEmpty {
                HStack(spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("^[\(cart.count) item](inflect: true) selected")
                            .font(Font.sift.headline)
                            .foregroundStyle(Color.sift.inkPrimary)
                        Text(ByteFormatter.string(cart.totalBytes))
                            .font(Font.sift.metric)
                            .foregroundStyle(Color.sift.inkSecondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: Spacing.s)
                    Button(action: onReview) {
                        Label("Review", systemImage: "checklist")
                            .font(Font.sift.headline)
                            .padding(.horizontal, Spacing.l)
                            .frame(minHeight: Layout.minTouchTarget)
                            .foregroundStyle(Color.sift.onAccent)
                            .background(Color.sift.accent, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(Color.sift.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onReview() }
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: cart.isEmpty)
        .animation(Motion.standard, value: cart.totalBytes)
    }
}

#Preview {
    let cart = CleanupCart()
    cart.add([.asset(id: "a", category: .screenshots, bytes: 1_400_000_000)])
    return Color.sift.canvas
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom) { SelectionBar(cart: cart) {} }
}
