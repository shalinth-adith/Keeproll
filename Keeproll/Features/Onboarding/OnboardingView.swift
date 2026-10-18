import SwiftUI

/// Welcome (how it works) → Set up access (Photos, Contacts, Calendar in one place). FR-PERM-1…3.
struct OnboardingView: View {
    let env: AppEnvironment
    @State private var step: Step = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable { case welcome, access }

    var body: some View {
        ZStack {
            Color.keeproll.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .access: AccessSetupPage(scanStore: env.scanStore, onFinish: finish)
                    }
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            // Reserved space above the home indicator, so the pages lay out above the
            // dots instead of pushing them off a 6.1-inch screen (QA L1).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                pageDots
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(Color.keeproll.canvas)
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.standard), value: step)
    }

    private var pageDots: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? Color.keeproll.accent : Color.keeproll.hairline)
                    .frame(width: s == step ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
    }

    private var welcome: some View {
        PermissionPrimer(
            hero: .custom(AnyView(OnboardingHero.Welcome())),
            title: Text("Keep what matters"),
            reasons: [
                Text("Scan: Keeproll finds similar photos, screenshots, blurry shots, large videos, duplicate contacts and old events."),
                Text("Review: you see every item and tap any to keep it. Nothing is removed until you confirm."),
                Text("Private: everything stays on your iPhone. No account, no upload."),
            ],
            allowTitle: "Okay, let's go"
        ) { step = .access }
    }

    private func finish() {
        Log.ui.debug("Onboarding finished")
        env.settings.hasCompletedOnboarding = true
        env.settings.lastSeenBuild = WhatsNew.currentBuild
        env.scanStore.scan()
    }
}
