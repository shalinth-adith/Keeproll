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
    private(set) var videos: Loadable<[MediaItem]> = .idle
    /// Groups stream in while the similarity scan runs; `similarProgress` is nil when idle.
    private(set) var similar: Loadable<[SimilarGroup]> = .idle
    private(set) var similarProgress: Double?
    private(set) var contacts: Loadable<[DuplicateContactGroup]> = .idle

    private let permissions: PermissionServicing
    private let storageService: DeviceStorageProviding
    private let photos: PhotoLibraryProviding
    private let similarity: SimilarityScanning?
    private let contactsScanner: ContactsScanning?
    private var scanTask: Task<Void, Never>?

    init(permissions: PermissionServicing,
         storage: DeviceStorageProviding,
         photos: PhotoLibraryProviding,
         similarity: SimilarityScanning? = nil,
         contactsScanner: ContactsScanning? = nil) {
        self.permissions = permissions
        self.storageService = storage
        self.photos = photos
        self.similarity = similarity
        self.contactsScanner = contactsScanner
        self.photosPermission = permissions.photosState()
        self.contactsPermission = permissions.contactsState()
    }

    /// Categories that have a scanner in this build, in dashboard order.
    var availableCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { category in
            switch category {
            case .screenshots, .videos: true
            case .similar: similarity != nil
            case .contacts: contactsScanner != nil
            }
        }
    }

    var screenshotBytes: Int64 { screenshots.value?.reduce(0) { $0 + ($1.byteSize ?? 0) } ?? 0 }
    var videoBytes: Int64 { videos.value?.reduce(0) { $0 + ($1.byteSize ?? 0) } ?? 0 }
    var similarBytes: Int64 { similar.value?.reduce(0) { $0 + $1.freeableBytes } ?? 0 }
    var similarPhotoCount: Int { similar.value?.reduce(0) { $0 + $1.othersThanBest.count } ?? 0 }
    var duplicateContactCount: Int { contacts.value?.reduce(0) { $0 + $1.contacts.count } ?? 0 }

    /// Re-reads permission state (for example on returning from Settings). Rescans if
    /// access changed.
    func refreshPermissions() {
        let newPhotos = permissions.photosState()
        let newContacts = permissions.contactsState()
        let changed = newPhotos != photosPermission || newContacts != contactsPermission
        photosPermission = newPhotos
        contactsPermission = newContacts
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
        Log.scan.debug("Scan started (photos: \(String(describing: self.photosPermission), privacy: .public), contacts: \(String(describing: self.contactsPermission), privacy: .public))")
        scanTask = Task {
            async let a: Void = loadStorage()
            async let b: Void = loadScreenshots()
            async let c: Void = loadVideos()
            async let d: Void = loadContacts()
            async let e: Void = loadSimilar()
            _ = await (a, b, c, d, e)
            Log.scan.debug("Scan finished")
        }
    }

    /// Removes deleted assets from every result list without a rescan.
    func removeAssets(_ ids: Set<String>) {
        if case .loaded(let items) = screenshots {
            screenshots = .loaded(items.filter { !ids.contains($0.id) })
        }
        if case .loaded(let items) = videos {
            videos = .loaded(items.filter { !ids.contains($0.id) })
        }
        if case .loaded(let groups) = similar {
            similar = .loaded(groups.compactMap { group in
                var group = group
                group.members.removeAll { ids.contains($0.id) }
                guard group.members.count > 1 else { return nil }
                if !group.members.contains(where: { $0.id == group.bestID }) { group.bestID = group.members[0].id }
                return group
            })
        }
        Task { await loadStorage() }
    }

    /// Removes contacts that were merged away or deleted.
    func removeContacts(_ ids: Set<String>) {
        if case .loaded(let groups) = contacts {
            contacts = .loaded(groups.compactMap { group in
                var group = group
                group.contacts.removeAll { ids.contains($0.id) }
                return group.contacts.count > 1 ? group : nil
            })
        }
    }

    /// Changes which member of a group is marked best (FR-SIM-3).
    func setBest(_ id: String, in groupID: UUID) {
        guard case .loaded(var groups) = similar, let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].bestID = id
        groups[index].members.sort { ($0.id == id ? 0 : 1) < ($1.id == id ? 0 : 1) }
        similar = .loaded(groups)
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
        guard photosPermission.canRead else { screenshots = .idle; return }
        if screenshots.value == nil { screenshots = .loading }
        let items = await photos.fetchScreenshots()
        guard !Task.isCancelled else { return }
        screenshots = .loaded(items)
    }

    private func loadVideos() async {
        guard photosPermission.canRead else { videos = .idle; return }
        if videos.value == nil { videos = .loading }
        let items = await photos.fetchVideos()
        guard !Task.isCancelled else { return }
        videos = .loaded(items)
    }

    private func loadContacts() async {
        guard let contactsScanner, contactsPermission.canRead else { contacts = .idle; return }
        if contacts.value == nil { contacts = .loading }
        let groups = await contactsScanner.findDuplicates()
        guard !Task.isCancelled else { return }
        contacts = .loaded(groups)
    }

    private func loadSimilar() async {
        guard let similarity, photosPermission.canRead else { similar = .idle; return }
        similar = .loading
        similarProgress = 0
        var groups: [SimilarGroup] = []
        for await group in similarity.scan() {
            guard !Task.isCancelled else { return }
            groups.append(group)
            similar = .loaded(groups) // stream groups in as they're found (FR-SIM-2)
        }
        similar = .loaded(groups)
        similarProgress = nil
    }
}
