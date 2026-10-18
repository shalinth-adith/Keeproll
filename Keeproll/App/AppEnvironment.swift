import Foundation

/// Dependency container. Built once in `KeeprollApp` and passed down explicitly, so every
/// ViewModel gets its services through its initialiser.
struct AppEnvironment {
    let permissions: PermissionServicing
    let thumbnails: ThumbnailProviding
    let videoPlayback: VideoPlaybackProviding
    let compression: VideoCompressing
    let livePhotos: LivePhotoConverting
    let trimmer: VideoTrimming
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
        // Contacts and calendar backups expire after 90 days (QA M2).
        BackupStore.prune()
        let cache = ScanCache()
        let sizes = AssetSizeService(cache: cache)
        let photos = PhotoLibraryService(sizes: sizes)
        let contacts = ContactsService()
        let calendar = CalendarService()
        let livePhotoService = LivePhotoService(sizes: sizes)
        let smartTrim = SmartTrimService(photos: photos, cache: cache)

        return AppEnvironment(
            permissions: permissions,
            thumbnails: ThumbnailProvider(),
            videoPlayback: VideoPlaybackService(),
            compression: VideoCompressionService(),
            livePhotos: livePhotoService,
            trimmer: smartTrim,
            vault: VaultStore(),
            vaultAuth: DeviceOwnerAuthenticator(),
            deletion: DeletionService(contacts: contacts, calendar: calendar),
            libraryMonitor: LibraryChangeMonitor(),
            scanStore: ScanStore(permissions: permissions, storage: DeviceStorageService(), photos: photos,
                                 similarity: SimilarityEngine(sizes: sizes, cache: cache), contactsScanner: contacts,
                                 calendarScanner: calendar,
                                 chatScanner: ChatMediaScanner(sizes: sizes, cache: cache),
                                 expiryScanner: ScreenshotExpiryScanner(photos: photos, cache: cache),
                                 livePhotoScanner: livePhotoService,
                                 trimScanner: smartTrim),
            cart: CleanupCart(),
            settings: SettingsStore(),
            router: AppRouter()
        )
    }
}
