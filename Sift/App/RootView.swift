import SwiftUI

/// Shows onboarding on first launch, then the dashboard with navigation and the Review sheet.
struct RootView: View {
    let env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    /// Watches the library once Photos access exists. Deleted photos disappear from every
    /// list and from the cart straight away.
    private func startLibraryMonitor() {
        guard env.scanStore.photosPermission.canRead else { return }
        let store = env.scanStore, cart = env.cart
        env.libraryMonitor.start { delta in
            let removed = store.apply(delta)
            cart.removeAssets(removed)
        }
    }

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
                            case .blurry: BlurryPhotosView(env: env)
                            case .videos: LargeVideosView(env: env)
                            case .contacts: DuplicateContactsView(env: env)
                            case .calendar: CalendarCleanupView(env: env)
                            case .vault: VaultView(env: env)
                            case .swipe: SwipeView(env: env)
                            case .calibration: CalibrationScreen(env: env)
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
                    case .compress(let item): CompressVideoSheet(item: item, env: env).environment(\.thumbnails, env.thumbnails)
                    }
                }
            } else {
                OnboardingView(env: env)
            }
        }
        .background(Color.sift.canvas)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            env.scanStore.refreshPermissions()
            startLibraryMonitor()
            // Back from the Camera or Photos with new or edited shots: refresh quietly.
            // The cache makes this a warm rescan (seconds, not a full re-analysis).
            if env.scanStore.isStale && !env.scanStore.isScanning { env.scanStore.scan() }
        }
        .task { startLibraryMonitor() }
    }
}
