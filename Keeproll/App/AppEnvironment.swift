import Foundation

/// Dependency container. Built once in `KeeprollApp` and passed down explicitly, so every
/// ViewModel gets its services through its initialiser.
struct AppEnvironment {
    let permissions: PermissionServicing
    let thumbnails: ThumbnailProviding
    let videoPlayback: VideoPlaybackProviding
    let compression: VideoCompressing
    let vault: VaultStoring
    let vaultAuth: VaultAuthenticating
    let deletion: DeletionServicing
    let libraryMonitor: LibraryChangeMonitoring
    let scanStore: ScanStore
    let cart: CleanupCart
    let settings: SettingsStore
    let router: AppRouter

    static func live() -> AppEnvironment {
        let permissions = PermissionService()
        #if DEBUG
        // `-KeeprollResetCache` launch argument: measure a cold scan without reinstalling.
        if ProcessInfo.processInfo.arguments.contains("-KeeprollResetCache") {
            try? FileManager.default.removeItem(at: ScanCache.defaultURL)
        }
        #endif
        let cache = ScanCache()
        let sizes = AssetSizeService(cache: cache)
        let photos = PhotoLibraryService(sizes: sizes)
        let contacts = ContactsService()
        let calendar = CalendarService()

        return AppEnvironment(
            permissions: permissions,
            thumbnails: ThumbnailProvider(),
            videoPlayback: VideoPlaybackService(),
            compression: VideoCompressionService(),
            vault: VaultStore(),
            vaultAuth: DeviceOwnerAuthenticator(),
            deletion: DeletionService(contacts: contacts, calendar: calendar),
            libraryMonitor: LibraryChangeMonitor(),
            scanStore: ScanStore(permissions: permissions, storage: DeviceStorageService(), photos: photos,
                                 similarity: SimilarityEngine(sizes: sizes, cache: cache), contactsScanner: contacts,
                                 calendarScanner: calendar),
            cart: CleanupCart(),
            settings: SettingsStore(),
            router: AppRouter()
        )
    }
}
