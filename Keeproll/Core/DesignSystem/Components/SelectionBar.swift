import SwiftUI

/// Sticky bottom bar shown whenever the cart has items (FR-DASH-4).
struct SelectionBar: View {
    let cart: CleanupCart
    let onReview: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ZStack {
            if !cart.isEmpty {
                // Side by side normally; stacked once the text can't share a line with the button.
                layout {
                    if typeSize.isAccessibilitySize {
                        // One line at large sizes, so the bar doesn't cover half the list (QA U1).
                        Text(cart.totalBytes > 0 ? "\(cart.count) · \(ByteFormatter.string(cart.totalBytes))" : "\(cart.count)")
                            .font(Font.keeproll.headline)
                            .foregroundStyle(Color.keeproll.inkPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(Text("^[\(cart.count) item](inflect: true) selected, \(ByteFormatter.string(cart.totalBytes))"))
                    } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("^[\(cart.count) item](inflect: true) selected")
                            .font(Font.keeproll.headline)
                            .foregroundStyle(Color.keeproll.inkPrimary)
                        // Contacts and events have no size; "0 MB" would suggest nothing happens.
                        if cart.totalBytes > 0 {
                            Text(ByteFormatter.string(cart.totalBytes))
                                .font(Font.keeproll.metric)
                                .foregroundStyle(Color.keeproll.inkSecondary)
                                .contentTransition(.numericText())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: onReview) {
                        Label("Review", systemImage: "checklist")
                            .font(Font.keeproll.headline)
                            .padding(.horizontal, Spacing.l)
                            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: Layout.minTouchTarget)
                            .foregroundStyle(Color.keeproll.onAccent)
                            .background(Color.keeproll.accent, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                // The bar floats over the list: past the first accessibility size it would
                // hide too much of it (QA U1).
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .background(Color.keeproll.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.keeproll.hairline))
                .shadow(color: Elevation.floatingColor, radius: Elevation.floatingRadius, y: Elevation.floatingY)
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

    @ViewBuilder private func layout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.s, content: content)
        } else {
            HStack(spacing: Spacing.m, content: content)
        }
    }
}

#Preview {
    let cart = CleanupCart()
    cart.add([.asset(id: "a", category: .screenshots, bytes: 1_400_000_000)])
    return Color.keeproll.canvas
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom) { SelectionBar(cart: cart) {} }
}
