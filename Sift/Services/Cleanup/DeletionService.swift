import Photos

/// THE ONLY place in the app that deletes anything (ARCHITECTURE §7, DECISIONS D10).
/// It accepts a `CleanupPlan`, which only `ReviewViewModel` can build.
nonisolated protocol DeletionServicing: Sendable {
    func execute(_ plan: CleanupPlan) async -> CleanupResult
}

nonisolated final class DeletionService: DeletionServicing {
    @concurrent
    func execute(_ plan: CleanupPlan) async -> CleanupResult {
        let signpost = Signposts.cleanup.beginInterval("cleanup.execute")
        defer { Signposts.cleanup.endInterval("cleanup.execute", signpost) }

        let ids = plan.assetIDs
        guard !ids.isEmpty else {
            return CleanupResult(deletedAssetIDs: [], bytesFreed: 0, countsByCategory: [:], failures: [], wasCancelled: false)
        }
        Log.cleanup.debug("Deleting \(ids.count) assets (\(plan.totalBytes) bytes planned)")

        do {
            // iOS shows its own confirmation here. We never suppress it (FR-REV-3).
            try await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            if let photosError = error as? PHPhotosError, photosError.code == .userCancelled {
                Log.cleanup.debug("User cancelled the system delete prompt; nothing deleted")
                return .cancelled
            }
            Log.cleanup.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            let failures = plan.items.map { CleanupFailure(itemKey: $0.key, reason: error.localizedDescription) }
            return CleanupResult(deletedAssetIDs: [], bytesFreed: 0, countsByCategory: [:], failures: failures, wasCancelled: false)
        }

        // performChanges is all-or-nothing, but confirm what is actually gone.
        let remaining = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var stillPresent = Set<String>()
        remaining.enumerateObjects { asset, _, _ in stillPresent.insert(asset.localIdentifier) }

        let deleted = plan.items.filter { !stillPresent.contains($0.assetID) }
        let failures = plan.items.filter { stillPresent.contains($0.assetID) }
            .map { CleanupFailure(itemKey: $0.key, reason: String(localized: "This item is still in your library.")) }
        let counts = Dictionary(grouping: deleted, by: \.category).mapValues(\.count)
        let bytes = deleted.reduce(Int64(0)) { $0 + $1.bytes }
        Log.cleanup.debug("Deleted \(deleted.count) assets, \(failures.count) failures, \(bytes) bytes")
        return CleanupResult(
            deletedAssetIDs: deleted.map(\.assetID),
            bytesFreed: bytes,
            countsByCategory: counts,
            failures: failures,
            wasCancelled: false
        )
    }
}
