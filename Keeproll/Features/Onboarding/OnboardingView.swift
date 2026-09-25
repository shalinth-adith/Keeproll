import SwiftUI

/// Welcome → Photos primer → Contacts primer (skippable). FR-PERM-1…3.
struct OnboardingView: View {
    let env: AppEnvironment
    @State private var step: Step = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable { case welcome, photos, contacts }

    var body: some View {
        ZStack {
            Color.keeproll.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .photos: photos
                    case .contacts: contacts
                    }
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                pageDots
                    .padding(.bottom, Spacing.m)
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
            hero: .brandMark,
            title: Text("Keep what matters"),
            reasons: [
                Text("Find similar photos, screenshots, large videos and duplicate contacts."),
                Text("You review everything before anything is removed."),
                Text("Everything stays on your iPhone. Nothing is uploaded."),
            ],
            allowTitle: "Get started"
        ) { step = .photos }
    }

    private var photos: some View {
        PermissionPrimer(
            hero: .symbol("photo.on.rectangle.angled"),
            title: Text("Let Keeproll look at your photos"),
            reasons: [
                Text("Keeproll checks photos and videos on this iPhone to find what's taking space."),
                Text("You can choose to share only some photos. Keeproll will still work."),
                Text("Nothing is ever deleted without your approval."),
            ],
            allowTitle: "Continue"
        ) {
            Task {
                await env.scanStore.requestPhotos()
                step = .contacts
            }
        }
    }

    private var contacts: some View {
        PermissionPrimer(
            hero: .symbol("person.2.circle"),
            title: Text("Find duplicate contacts"),
            reasons: [
                Text("Keeproll can spot the same person saved more than once."),
                Text("Merged contacts keep every number and email."),
                Text("You can skip this and turn it on later."),
            ],
            allowTitle: "Continue",
            onAllow: {
                Task {
                    await env.scanStore.requestContacts()
                    finish()
                }
            },
            onSkip: finish
        )
    }

    private func finish() {
        Log.ui.debug("Onboarding finished")
        env.settings.hasCompletedOnboarding = true
        env.scanStore.scan()
    }
}
