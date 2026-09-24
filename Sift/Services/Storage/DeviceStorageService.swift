import Foundation

nonisolated protocol DeviceStorageProviding: Sendable {
    func snapshot() async throws -> StorageSnapshot
}

nonisolated final class DeviceStorageService: DeviceStorageProviding {
    @concurrent
    func snapshot() async throws -> StorageSnapshot {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { throw AppError.storageUnavailable }
        let snapshot = StorageSnapshot(totalBytes: Int64(total), availableBytes: available)
        Log.scan.debug("Storage snapshot: total=\(snapshot.totalBytes) available=\(snapshot.availableBytes)")
        return snapshot
    }
}
