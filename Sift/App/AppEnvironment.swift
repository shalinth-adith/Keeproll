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
        let sizes = AssetSizeService()
        let photos = PhotoLibraryService(sizes: sizes)

        var similarity: SimilarityScanning? = nil
        var contactsScanner: ContactsScanning? = nil
        #if DEBUG
        // `SIFT_DEMO=1` in the scheme's environment feeds fixture results into the
        // categories whose scanners aren't built yet, so the UI can be exercised.
        if ProcessInfo.processInfo.environment["SIFT_DEMO"] == "1" {
            similarity = DemoSimilarity(photos: photos)
            contactsScanner = DemoContacts()
        }
        #endif

        return AppEnvironment(
            permissions: permissions,
            thumbnails: ThumbnailProvider(),
            videoPlayback: VideoPlaybackService(),
            deletion: DeletionService(),
            scanStore: ScanStore(permissions: permissions, storage: DeviceStorageService(), photos: photos,
                                 similarity: similarity, contactsScanner: contactsScanner),
            cart: CleanupCart(),
            settings: SettingsStore(),
            router: AppRouter()
        )
    }
}
