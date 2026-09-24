import SwiftUI

/// Shows onboarding on first launch, then the dashboard with navigation and the Review sheet.
struct RootView: View {
    let env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = env.router
        Group {
            if env.settings.hasCompletedOnboarding {
                NavigationStack(path: $router.path) {
                    DashboardView(env: env)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .similar: SimilarPhotosView(env: env)
                            case .screenshots: ScreenshotsView(env: env)
                            case .videos: LargeVideosView(env: env)
                            case .contacts: DuplicateContactsView(env: env)
                            case .swipe: SwipeView(env: env)
                            case .compare(let groupID, let startID): CompareView(env: env, groupID: groupID, startID: startID)
                            }
                        }
                }
                .safeAreaInset(edge: .bottom) {
                    if !router.hidesSelectionBar {
                        SelectionBar(cart: env.cart) { router.presentReview() }
                    }
                }
                .sheet(item: $router.sheet) { sheet in
                    switch sheet {
                    case .review: ReviewFlowView(env: env)
                    case .videoPreview(let id): VideoPreviewView(id: id, playback: env.videoPlayback)
                    }
                }
            } else {
                OnboardingView(env: env)
            }
        }
        .background(Color.sift.canvas)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { env.scanStore.refreshPermissions() }
        }
    }
}
