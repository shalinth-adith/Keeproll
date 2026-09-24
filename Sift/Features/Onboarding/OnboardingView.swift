import SwiftUI

/// Welcome → Photos primer → Contacts primer (skippable). FR-PERM-1…3.
struct OnboardingView: View {
    let env: AppEnvironment
    @State private var step: Step = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step { case welcome, photos, contacts }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                PermissionPrimer(
                    systemImage: "sparkles.rectangle.stack",
                    title: Text("Keep what matters"),
                    reasons: [
                        Text("Find similar photos, screenshots, large videos and duplicate contacts."),
                        Text("You review everything before anything is removed."),
                        Text("Everything stays on your iPhone. Nothing is uploaded."),
                    ],
                    allowTitle: "Get started"
                ) { advance(to: .photos) }
            case .photos:
                PermissionPrimer(
                    systemImage: "photo.on.rectangle.angled",
                    title: Text("Let Sift look at your photos"),
                    reasons: [
                        Text("Sift checks photos and videos on this iPhone to find what's taking space."),
                        Text("You can choose to share only some photos. Sift will still work."),
                        Text("Nothing is ever deleted without your approval."),
                    ],
                    allowTitle: "Continue"
                ) {
                    Task {
                        await env.scanStore.requestPhotos()
                        advance(to: .contacts)
                    }
                }
            case .contacts:
                PermissionPrimer(
                    systemImage: "person.2.circle",
                    title: Text("Find duplicate contacts"),
                    reasons: [
                        Text("Sift can spot the same person saved more than once."),
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
        }
        .transition(.opacity)
    }

    private func advance(to next: Step) {
        withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { step = next }
    }

    private func finish() {
        Log.ui.debug("Onboarding finished")
        env.settings.hasCompletedOnboarding = true
        env.scanStore.scan()
    }
}
