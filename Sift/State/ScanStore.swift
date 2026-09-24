import Observation
import Foundation

/// Loading state for one category's results.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

/// App-wide scan results and permission state, shared by the dashboard and every
/// category screen.
@Observable
final class ScanStore {
    private(set) var photosPermission: PermissionState
    private(set) var contactsPermission: PermissionState
    private(set) var storage: Loadable<StorageSnapshot> = .idle
    private(set) var screenshots: Loadable<[MediaItem]> = .idle

    private let permissions: PermissionServicing
    private let storageService: DeviceStorageProviding
    private let photos: PhotoLibraryProviding
    private var scanTask: Task<Void, Never>?

    init(permissions: PermissionServicing, storage: DeviceStorageProviding, photos: PhotoLibraryProviding) {
        self.permissions = permissions
        self.storageService = storage
        self.photos = photos
        self.photosPermission = permissions.photosState()
        self.contactsPermission = permissions.contactsState()
    }

    var screenshotBytes: Int64 {
        screenshots.value?.reduce(0) { $0 + ($1.byteSize ?? 0) } ?? 0
    }

    /// Re-reads permission state (for example on returning from Settings). Rescans if
    /// Photos access changed.
    func refreshPermissions() {
        let newPhotos = permissions.photosState()
        let changed = newPhotos != photosPermission
        photosPermission = newPhotos
        contactsPermission = permissions.contactsState()
        if changed { scan() }
    }

    func requestPhotos() async {
        photosPermission = await permissions.requestPhotos()
    }

    func requestContacts() async {
        contactsPermission = await permissions.requestContacts()
    }

    /// Runs every category scan concurrently, cheapest first. Cancels any scan in flight.
    func scan() {
        scanTask?.cancel()
        Log.scan.debug("Scan started (photos permission: \(String(describing: self.photosPermission), privacy: .public))")
        scanTask = Task {
            async let storageDone: Void = loadStorage()
            async let screenshotsDone: Void = loadScreenshots()
            _ = await (storageDone, screenshotsDone)
            Log.scan.debug("Scan finished")
        }
    }

    /// Removes deleted assets from every result list without a rescan.
    func removeAssets(_ ids: Set<String>) {
        if case .loaded(let items) = screenshots {
            screenshots = .loaded(items.filter { !ids.contains($0.id) })
        }
        Task { await loadStorage() }
    }

    private func loadStorage() async {
        if storage.value == nil { storage = .loading }
        do {
            storage = .loaded(try await storageService.snapshot())
        } catch {
            storage = .failed(.storageUnavailable)
        }
    }

    private func loadScreenshots() async {
        guard photosPermission.canRead else {
            screenshots = .idle
            return
        }
        if screenshots.value == nil { screenshots = .loading }
        let items = await photos.fetchScreenshots()
        guard !Task.isCancelled else { return }
        screenshots = .loaded(items)
    }
}
