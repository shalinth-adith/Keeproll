import Foundation

/// Dependency container. Built once in `SiftApp` and passed down explicitly, so every
/// ViewModel gets its services through its initialiser.
struct AppEnvironment {
    let permissions: PermissionServicing
    let thumbnails: ThumbnailProviding
    let videoPlayback: VideoPlaybackProviding
    let deletion: DeletionServicing
    let scanStore: ScanStore
    let cart: CleanupCart
    let settings: SettingsStore
    let router: AppRouter

    static func live() -> AppEnvironment {
        let permissions = PermissionService()
        #if DEBUG
        // `-SiftResetCache` launch argument: measure a cold scan without reinstalling.
        if ProcessInfo.processInfo.arguments.contains("-SiftResetCache") {
            try? FileManager.default.removeItem(at: ScanCache.defaultURL)
        }
        #endif
        let cache = ScanCache()
        let sizes = AssetSizeService(cache: cache)
        let photos = PhotoLibraryService(sizes: sizes)
        let contacts = ContactsService()

        return AppEnvironment(
            permissions: permissions,
            thumbnails: ThumbnailProvider(),
            videoPlayback: VideoPlaybackService(),
            deletion: DeletionService(contacts: contacts),
            scanStore: ScanStore(permissions: permissions, storage: DeviceStorageService(), photos: photos,
                                 similarity: SimilarityEngine(sizes: sizes, cache: cache), contactsScanner: contacts),
            cart: CleanupCart(),
            settings: SettingsStore(),
            router: AppRouter()
        )
    }
}
