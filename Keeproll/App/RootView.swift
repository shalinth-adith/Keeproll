import SwiftUI

/// Shows onboarding on first launch, then the dashboard with navigation and the Review sheet.
struct RootView: View {
    let env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWhatsNew = false

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
                    HomeView(env: env)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .dashboard: DashboardView(env: env)
                            case .settings: SettingsView(env: env)
                            case .similar: SimilarPhotosView(env: env)
                            case .screenshots: ScreenshotsView(env: env)
                            case .blurry: BlurryPhotosView(env: env)
                            case .accidental: AccidentalShotsView(env: env)
                            case .trims: SmartTrimView(env: env)
                            case .videos: LargeVideosView(env: env)
                            case .chats: ChatSavedView(env: env)
                            case .expired: ExpiredScreenshotsView(env: env)
                            case .livePhotos: LivePhotosView(env: env)
                            case .contacts: DuplicateContactsView(env: env)
                            case .calendar: CalendarCleanupView(env: env)
                            case .vault: VaultView(env: env)
                            case .swipe: SwipeView(env: env)
                            case .calibration: CalibrationScreen(env: env)
                            case .compare(let groupID, let startID): CompareView(env: env, groupID: groupID, startID: startID)
                            }
                        }
                }
                // A rescan can change contact groups; queued changes that no longer
                // match are dropped (QA H4).
                .onChange(of: env.scanStore.contactsLoadCount) { _, _ in
                    env.cart.pruneContacts(to: env.scanStore.contacts.value ?? [])
                }
                .onChange(of: env.scanStore.calendarLoadCount) { _, _ in
                    env.cart.pruneCalendar(to: env.scanStore.calendar.value)
                }
                .safeAreaInset(edge: .bottom) {
                    if !router.hidesSelectionBar {
                        SelectionBar(cart: env.cart) { router.presentReview() }
                    }
                }
                .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet(items: WhatsNew.items()) {
                env.settings.lastSeenBuild = WhatsNew.currentBuild
                showWhatsNew = false
            }
        }
        .sheet(item: $router.sheet) { sheet in
                    switch sheet {
                    case .review: ReviewFlowView(env: env)
                    case .videoPreview(let id): VideoPreviewView(id: id, playback: env.videoPlayback)
                    case .compress(let item): CompressVideoSheet(item: item, env: env).environment(\.thumbnails, env.thumbnails)
                    case .convertLivePhotos(let items): ConvertLivePhotosSheet(items: items, env: env).environment(\.thumbnails, env.thumbnails)
                    case .trim(let candidate): TrimVideoSheet(candidate: candidate, env: env).environment(\.thumbnails, env.thumbnails)
                    }
                }
            } else {
                OnboardingView(env: env)
            }
        }
        .background(Color.keeproll.canvas)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            env.scanStore.refreshPermissions()
            startLibraryMonitor()
            // Back from the Camera or Photos with new or edited shots: refresh quietly.
            // The cache makes this a warm rescan (seconds, not a full re-analysis).
            if env.scanStore.isStale && !env.scanStore.isScanning { env.scanStore.scan() }
        }
        .task {
            env.settings.recordSession()
            DiagnosticsService.shared.start()
            if env.settings.hasCompletedOnboarding {
                if WhatsNew.shouldShow(lastSeen: env.settings.lastSeenBuild) { showWhatsNew = true }
                else if env.settings.lastSeenBuild == nil { env.settings.lastSeenBuild = WhatsNew.currentBuild } // installs that predate the sheet
            }
            startLibraryMonitor()
            #if DEBUG
            if env.scanStore.photosPermission.canRead {
                await LivePhotoSeedFixtures.seedIfRequested()
            }
            #endif
        }
    }
}
