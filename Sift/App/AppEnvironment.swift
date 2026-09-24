import Foundation

/// Dependency container. Built once in `SiftApp` and passed down explicitly, so every
/// ViewModel gets its services through its initialiser.
struct AppEnvironment {
    let permissions: PermissionServicing
    let thumbnails: ThumbnailProviding
    let deletion: DeletionServicing
    let scanStore: ScanStore
    let cart: CleanupCart
    let settings: SettingsStore
    let router: AppRouter

    static func live() -> AppEnvironment {
        let permissions = PermissionService()
        let sizes = AssetSizeService()
        let photos = PhotoLibraryService(sizes: sizes)
        return AppEnvironment(
            permissions: permissions,
            thumbnails: ThumbnailProvider(),
            deletion: DeletionService(),
            scanStore: ScanStore(permissions: permissions, storage: DeviceStorageService(), photos: photos),
            cart: CleanupCart(),
            settings: SettingsStore(),
            router: AppRouter()
        )
    }
}
