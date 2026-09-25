import Foundation
@testable import Keeproll

nonisolated struct FakeSimilarity: SimilarityScanning {
    let events: [SimilarityEvent]
    func scan() -> AsyncStream<SimilarityEvent> {
        AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

nonisolated final class FakePermissions: PermissionServicing, @unchecked Sendable {
    var photos: PermissionState
    var contacts: PermissionState
    init(photos: PermissionState = .authorized, contacts: PermissionState = .authorized) {
        self.photos = photos
        self.contacts = contacts
    }
    func photosState() -> PermissionState { photos }
    func requestPhotos() async -> PermissionState { photos }
    func contactsState() -> PermissionState { contacts }
    func requestContacts() async -> PermissionState { contacts }
    func calendarState() -> PermissionState { .denied }
    func requestCalendar() async -> PermissionState { .denied }
}

nonisolated struct FakeStorage: DeviceStorageProviding {
    func snapshot() async throws -> StorageSnapshot {
        StorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 20_000_000_000)
    }
}

nonisolated struct FakePhotos: PhotoLibraryProviding {
    let screenshots: [MediaItem]
    var videos: [MediaItem] = []
    func fetchScreenshots() async -> [MediaItem] { screenshots }
    func fetchVideos() async -> [MediaItem] { videos }
}

/// Records the plan it was given and returns a scripted result.
actor FakeDeletion: DeletionServicing {
    enum Behaviour { case deleteAll, cancel }
    let behaviour: Behaviour
    private(set) var executedPlans: [CleanupPlan] = []

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func execute(_ plan: CleanupPlan) async -> CleanupResult {
        executedPlans.append(plan)
        switch behaviour {
        case .cancel:
            return .cancelled
        case .deleteAll:
            var counts = Dictionary(grouping: plan.items, by: \.category).mapValues(\.count)
            if !plan.contactActions.isEmpty { counts[.contacts] = plan.contactActions.count }
            return CleanupResult(deletedAssetIDs: plan.assetIDs, bytesFreed: plan.totalBytes,
                                 countsByCategory: counts, failures: [], wasCancelled: false)
        }
    }
}

enum Fixtures {
    static func screenshot(_ id: String, bytes: Int64 = 1_000_000, daysAgo: Double = 1, now: Date = Date()) -> MediaItem {
        MediaItem(id: id, kind: .screenshot, creationDate: now.addingTimeInterval(-daysAgo * 86_400),
                  pixelWidth: 1179, pixelHeight: 2556, duration: nil, isFavorite: false, byteSize: bytes)
    }

    @MainActor
    static func scanStore(screenshots: [MediaItem], photos: PermissionState = .authorized,
                          similarity: SimilarityScanning? = nil, defaults: UserDefaults? = nil) -> ScanStore {
        ScanStore(permissions: FakePermissions(photos: photos), storage: FakeStorage(), photos: FakePhotos(screenshots: screenshots),
                  similarity: similarity,
                  defaults: defaults ?? UserDefaults(suiteName: "KeeprollTests-\(UUID().uuidString)")!)
    }

    @MainActor
    static func settings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "KeeprollTests-\(UUID().uuidString)")!)
    }
}
