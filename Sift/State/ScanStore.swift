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

/// What the dashboard showed after the last completed scan, so the next launch can show
/// it instantly while a fresh scan runs.
nonisolated struct ScanSummary: Codable, Sendable, Equatable {
    var bytes: [String: Int64] = [:]
    var counts: [String: Int] = [:]
    var totalFreeable: Int64 = 0

    private static let key = "lastScanSummary"

    static func load(from defaults: UserDefaults = .standard) -> ScanSummary? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ScanSummary.self, from: $0) }
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
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
    /// Photos the similarity scan scored as out of focus (bonus: blurry detection).
    private(set) var blurry: Loadable<[MediaItem]> = .idle
    private(set) var contacts: Loadable<[DuplicateContactGroup]> = .idle
    #if DEBUG
    /// Statistics from the last similar-photo scan, for the calibration screen.
    private(set) var calibration: CalibrationData?
    #endif

    /// The previous scan's numbers, shown until this scan's arrive.
    private(set) var lastSummary: ScanSummary?
    /// A scan is running (results may still change).
    private(set) var isScanning = false

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
        self.lastSummary = ScanSummary.load()
    }

    /// Categories that have a scanner in this build, in dashboard order.
    var availableCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { category in
            switch category {
            case .screenshots, .videos: true
            case .similar, .blurry: similarity != nil
            case .contacts: contactsScanner != nil
            }
        }
    }

    var screenshotBytes: Int64 { screenshots.value?.reduce(0) { $0 + ($1.byteSize ?? 0) } ?? 0 }
    var videoBytes: Int64 { videos.value?.reduce(0) { $0 + ($1.byteSize ?? 0) } ?? 0 }
    var similarBytes: Int64 { similar.value?.reduce(0) { $0 + $1.freeableBytes } ?? 0 }
    var blurryBytes: Int64 { blurry.value?.reduce(0) { $0 + ($1.byteSize ?? 0) } ?? 0 }

    /// Everything that can be freed, counting each asset once even if it appears in
    /// several categories (FR-DASH-6).
    var totalFreeableBytes: Int64 {
        var seen = Set<String>()
        var total: Int64 = 0
        let candidates = (screenshots.value ?? []) + (videos.value ?? []) + (blurry.value ?? [])
            + (similar.value ?? []).flatMap(\.othersThanBest)
        for item in candidates where seen.insert(item.id).inserted { total += item.byteSize ?? 0 }
        return total
    }
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
        isScanning = true
        scanTask = Task {
            defer { if !Task.isCancelled { isScanning = false } }
            async let a: Void = loadStorage()
            async let b: Void = loadScreenshots()
            async let c: Void = loadVideos()
            async let d: Void = loadContacts()
            async let e: Void = loadSimilar()
            _ = await (a, b, c, d, e)
            guard !Task.isCancelled else { return }
            saveSummary()
            WidgetBridge.update(freeableBytes: totalFreeableBytes)
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
        if case .loaded(let items) = blurry {
            blurry = .loaded(items.filter { !ids.contains($0.id) })
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
        saveSummary()
        WidgetBridge.update(freeableBytes: totalFreeableBytes)
        Task { await loadStorage() }
    }

    /// Live number for a category if its scan has finished, else the last known one.
    func displayBytes(_ category: CleanupCategory) -> Int64? {
        if isLoaded(category) { return liveBytes(category) }
        return lastSummary?.bytes[category.rawValue]
    }

    func displayCount(_ category: CleanupCategory) -> Int? {
        if isLoaded(category) { return liveCount(category) }
        return lastSummary?.counts[category.rawValue]
    }

    func isLoaded(_ category: CleanupCategory) -> Bool {
        switch category {
        case .screenshots: screenshots.value != nil
        case .videos: videos.value != nil
        case .similar: similar.value != nil && similarProgress == nil
        case .blurry: blurry.value != nil && similarProgress == nil
        case .contacts: contacts.value != nil
        }
    }

    private func liveBytes(_ category: CleanupCategory) -> Int64 {
        switch category {
        case .screenshots: screenshotBytes
        case .videos: videoBytes
        case .similar: similarBytes
        case .blurry: blurryBytes
        case .contacts: 0
        }
    }

    private func liveCount(_ category: CleanupCategory) -> Int {
        switch category {
        case .screenshots: screenshots.value?.count ?? 0
        case .videos: videos.value?.count ?? 0
        case .similar: similarPhotoCount
        case .blurry: blurry.value?.count ?? 0
        case .contacts: duplicateContactCount
        }
    }

    private func saveSummary() {
        var summary = ScanSummary()
        for category in availableCategories where isLoaded(category) {
            summary.bytes[category.rawValue] = liveBytes(category)
            summary.counts[category.rawValue] = liveCount(category)
        }
        summary.totalFreeable = totalFreeableBytes
        summary.save()
        lastSummary = summary
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
        guard let similarity, photosPermission.canRead else {
            similar = .idle
            blurry = .idle
            return
        }
        if similar.value == nil { similar = .loading }
        similarProgress = 0
        var groups: [UUID: SimilarGroup] = [:]
        var order: [UUID] = []
        var blurryItems: [MediaItem] = []
        var lastPublish = Date.distantPast

        for await event in similarity.scan() {
            guard !Task.isCancelled else { return }
            switch event {
            case .progress(let processed, let total):
                similarProgress = total > 0 ? Double(processed) / Double(total) : 1
            case .upsert(let group):
                if groups[group.id] == nil { order.append(group.id) }
                groups[group.id] = group
            case .remove(let id):
                groups[id] = nil
                order.removeAll { $0 == id }
            case .blurry(let items):
                blurryItems.append(contentsOf: items)
            #if DEBUG
            case .calibration(let data):
                calibration = data
            #endif
            }
            // Publish at most twice a second: re-sorting and re-diffing a thousand groups
            // more often than that makes scrolling stutter on big libraries.
            if Date().timeIntervalSince(lastPublish) > 0.5 {
                publish(order.compactMap { groups[$0] }, blurryItems)
                lastPublish = Date()
            }
        }
        publish(order.compactMap { groups[$0] }, blurryItems)
        similarProgress = nil
    }

    /// Newest groups first, as the list reads (FR-SIM-2).
    private func publish(_ groups: [SimilarGroup], _ blurryItems: [MediaItem]) {
        similar = .loaded(groups.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
        blurry = .loaded(blurryItems.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) })
    }
}
