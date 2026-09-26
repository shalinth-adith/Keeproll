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
    /// When the scan that produced these numbers finished (nil for summaries saved before v4).
    var finishedAt: Date? = nil

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
    private(set) var calendarPermission: PermissionState
    /// Old and duplicate calendar events (bonus: calendar cleanup).
    private(set) var calendar: Loadable<CalendarFindings> = .idle
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
    /// Photos were added or edited in the library since the last scan finished.
    private(set) var isStale = false
    /// Photos the user explicitly chose as Best. A rescan recomputes groups from scratch,
    /// so without this their choice would silently revert and the photo they meant to
    /// keep would be offered for deletion (test report F2).
    private(set) var bestOverrides: Set<String>
    /// Library changes arriving before this moment were caused by Keeproll's own deletions
    /// and don't mean the results are out of date.
    private var ownChangesUntil = Date.distantPast
    /// Videos that already have a compressed copy (and the copies themselves), so
    /// compressing isn't offered twice for the same clip.
    private(set) var compressedVideos: Set<String>
    private let defaults: UserDefaults
    private static let bestOverridesKey = "bestOverrides"
    private static let compressedVideosKey = "compressedVideos"

    private let permissions: PermissionServicing
    private let storageService: DeviceStorageProviding
    private let photos: PhotoLibraryProviding
    private let similarity: SimilarityScanning?
    private let contactsScanner: ContactsScanning?
    private let calendarScanner: CalendarScanning?
    private var scanTask: Task<Void, Never>?

    init(permissions: PermissionServicing,
         storage: DeviceStorageProviding,
         photos: PhotoLibraryProviding,
         similarity: SimilarityScanning? = nil,
         contactsScanner: ContactsScanning? = nil,
         calendarScanner: CalendarScanning? = nil,
         defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bestOverrides = Set(defaults.stringArray(forKey: Self.bestOverridesKey) ?? [])
        self.compressedVideos = Set(defaults.stringArray(forKey: Self.compressedVideosKey) ?? [])
        self.permissions = permissions
        self.storageService = storage
        self.photos = photos
        self.similarity = similarity
        self.contactsScanner = contactsScanner
        self.calendarScanner = calendarScanner
        self.calendarPermission = permissions.calendarState()
        self.photosPermission = permissions.photosState()
        self.contactsPermission = permissions.contactsState()
        self.lastSummary = ScanSummary.load(from: defaults)
    }

    /// Categories that have a scanner in this build, in dashboard order.
    var availableCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { category in
            switch category {
            case .screenshots, .videos: true
            case .similar, .blurry: similarity != nil
            case .contacts: contactsScanner != nil
            case .calendar: calendarScanner != nil
            case .vault: false // reached from its own entry, never a scan card
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
        let newCalendar = permissions.calendarState()
        let changed = newPhotos != photosPermission || newContacts != contactsPermission || newCalendar != calendarPermission
        calendarPermission = newCalendar
        photosPermission = newPhotos
        contactsPermission = newContacts
        if changed { scan() }
    }

    func requestPhotos() async {
        photosPermission = await permissions.requestPhotos()
    }

    func requestCalendar() async {
        calendarPermission = await permissions.requestCalendar()
    }

    func requestContacts() async {
        contactsPermission = await permissions.requestContacts()
    }

    /// Runs every category scan concurrently, cheapest first. Cancels any scan in flight.
    func scan() {
        scanTask?.cancel()
        Log.scan.debug("Scan started (photos: \(String(describing: self.photosPermission), privacy: .public), contacts: \(String(describing: self.contactsPermission), privacy: .public))")
        isScanning = true
        isStale = false
        scanTask = Task {
            defer { if !Task.isCancelled { isScanning = false } }
            async let a: Void = loadStorage()
            async let b: Void = loadScreenshots()
            async let c: Void = loadVideos()
            async let d: Void = loadContacts()
            async let f: Void = loadCalendar()
            async let e: Void = loadSimilar()
            _ = await (a, b, c, d, e, f)
            guard !Task.isCancelled else { return }
            saveSummary()
            WidgetBridge.update(freeableBytes: totalFreeableBytes)
            Log.scan.debug("Scan finished")
        }
    }

    /// Removes deleted assets from every result list without a rescan.
    func removeAssets(_ ids: Set<String>) {
        if !bestOverrides.isDisjoint(with: ids) {
            bestOverrides.subtract(ids)
            saveBestOverrides()
        }
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
        case .calendar: calendar.value != nil
        case .vault: false
        }
    }

    private func liveBytes(_ category: CleanupCategory) -> Int64 {
        switch category {
        case .screenshots: screenshotBytes
        case .videos: videoBytes
        case .similar: similarBytes
        case .blurry: blurryBytes
        case .contacts, .calendar, .vault: 0
        }
    }

    private func liveCount(_ category: CleanupCategory) -> Int {
        switch category {
        case .screenshots: screenshots.value?.count ?? 0
        case .videos: videos.value?.count ?? 0
        case .similar: similarPhotoCount
        case .blurry: blurry.value?.count ?? 0
        case .contacts: duplicateContactCount
        case .calendar: calendar.value?.suggestionCount ?? 0
        case .vault: 0
        }
    }

    private func saveSummary() {
        var summary = ScanSummary()
        for category in availableCategories where isLoaded(category) {
            summary.bytes[category.rawValue] = liveBytes(category)
            summary.counts[category.rawValue] = liveCount(category)
        }
        summary.totalFreeable = totalFreeableBytes
        summary.finishedAt = Date()
        summary.save()
        lastSummary = summary
    }

    /// Applies a photo-library change (ARCHITECTURE §6.4). Removals take effect at once
    /// (cheap, and never pull a list out from under the user); additions and edits only
    /// mark results stale, to be picked up by a rescan. Returns the ids to drop from the cart.
    @discardableResult
    func apply(_ delta: LibraryDelta, now: Date = Date()) -> Set<String> {
        let known = knownAssetIDs
        let removed = delta.removedIDs.intersection(known)
        if !removed.isEmpty { removeAssets(removed) }
        // Deleting assets also "changes" albums and moments; after our own delete that
        // isn't new content, so don't trigger a rescan for it.
        let causedByKeeproll = now < ownChangesUntil
        if delta.hasAdditionsOrEdits && !isScanning && !causedByKeeproll { isStale = true }
        return removed
    }

    /// Called just before Keeproll itself deletes, so the resulting library notifications
    /// aren't mistaken for new photos.
    func expectOwnChanges(for seconds: TimeInterval = 10, now: Date = Date()) {
        ownChangesUntil = now.addingTimeInterval(seconds)
    }

    /// Every asset id currently shown in any category.
    var knownAssetIDs: Set<String> {
        var ids = Set<String>()
        for item in (screenshots.value ?? []) + (videos.value ?? []) + (blurry.value ?? []) { ids.insert(item.id) }
        for group in similar.value ?? [] { for member in group.members { ids.insert(member.id) } }
        return ids
    }

    /// Assets whose original is only in iCloud, across every category.
    var cloudOnlyIDs: Set<String> {
        var ids = Set<String>()
        for item in (screenshots.value ?? []) + (videos.value ?? []) + (blurry.value ?? []) where item.isCloudOnly { ids.insert(item.id) }
        for group in similar.value ?? [] { for member in group.members where member.isCloudOnly { ids.insert(member.id) } }
        return ids
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
        // One choice per group: the new pick replaces any earlier pick in the same group.
        bestOverrides.subtract(groups[index].members.map(\.id))
        bestOverrides.insert(id)
        saveBestOverrides()
        groups[index] = Self.applyingBest(id, to: groups[index])
        similar = .loaded(groups)
    }

    /// Re-applies the user's Best choices to freshly scanned groups.
    private func applyingOverrides(_ group: SimilarGroup) -> SimilarGroup {
        guard let chosen = group.members.first(where: { bestOverrides.contains($0.id) }),
              chosen.id != group.bestID else { return group }
        return Self.applyingBest(chosen.id, to: group)
    }

    private static func applyingBest(_ id: String, to group: SimilarGroup) -> SimilarGroup {
        var group = group
        group.bestID = id
        group.members.sort { ($0.id == id ? 0 : 1) < ($1.id == id ? 0 : 1) }
        return group
    }

    func markCompressed(original: String, copy: String) {
        compressedVideos.formUnion([original, copy])
        defaults.set(Array(compressedVideos), forKey: Self.compressedVideosKey)
    }

    private func saveBestOverrides() {
        defaults.set(Array(bestOverrides), forKey: Self.bestOverridesKey)
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

    private func loadCalendar() async {
        guard let calendarScanner, calendarPermission.canRead else { calendar = .idle; return }
        if calendar.value == nil { calendar = .loading }
        let findings = await calendarScanner.findCleanup()
        guard !Task.isCancelled else { return }
        calendar = .loaded(findings)
    }

    /// Removes calendar events that were deleted.
    func removeCalendarEvents(_ ids: Set<String>) {
        guard !ids.isEmpty, case .loaded(let findings) = calendar else { return }
        calendar = .loaded(findings.removing(ids))
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
        similar = .loaded(groups.map(applyingOverrides).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
        blurry = .loaded(blurryItems.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) })
    }
}
