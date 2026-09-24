import Photos

/// THE ONLY place in the app that deletes anything (ARCHITECTURE §7, DECISIONS D10).
/// It accepts a `CleanupPlan`, which only `ReviewViewModel` can build.
nonisolated protocol DeletionServicing: Sendable {
    func execute(_ plan: CleanupPlan) async -> CleanupResult
}

/// Applies contact merges and deletes (live: `ContactsService`). Without one, contact
/// actions are reported as failures, never silently dropped.
nonisolated protocol ContactsMutating: Sendable {
    /// Returns the backup file URL and the keys of actions that failed with a reason.
    func apply(_ actions: [CleanupPlan.ContactAction]) async -> (backup: URL?, failures: [CleanupFailure])
}

/// Deletes approved calendar events (live: `CalendarService`), after an .ics backup.
nonisolated protocol CalendarMutating: Sendable {
    func delete(_ events: [CleanupPlan.CalendarEvent]) async -> (backup: URL?, failures: [CleanupFailure])
}

nonisolated final class DeletionService: DeletionServicing {
    private let contacts: ContactsMutating?
    private let calendar: CalendarMutating?

    init(contacts: ContactsMutating? = nil, calendar: CalendarMutating? = nil) {
        self.contacts = contacts
        self.calendar = calendar
    }

    @concurrent
    func execute(_ plan: CleanupPlan) async -> CleanupResult {
        let signpost = Signposts.cleanup.beginInterval("cleanup.execute")
        defer { Signposts.cleanup.endInterval("cleanup.execute", signpost) }

        var deleted: [CleanupPlan.Item] = []
        var failures: [CleanupFailure] = []

        // 1. Photos and videos. iOS shows its own confirmation here; we never suppress it (FR-REV-3).
        if !plan.assetIDs.isEmpty {
            Log.cleanup.debug("Deleting \(plan.assetIDs.count) assets (\(plan.totalBytes) bytes planned)")
            do {
                let ids = plan.assetIDs
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
                }
                // performChanges is all-or-nothing, but confirm what is actually gone.
                var stillPresent = Set<String>()
                PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
                    stillPresent.insert(asset.localIdentifier)
                }
                deleted = plan.items.filter { !stillPresent.contains($0.assetID) }
                failures += plan.items.filter { stillPresent.contains($0.assetID) }
                    .map { CleanupFailure(itemKey: $0.key, reason: String(localized: "This item is still in your library.")) }
            } catch {
                if let photosError = error as? PHPhotosError, photosError.code == .userCancelled {
                    Log.cleanup.debug("User cancelled the system delete prompt; nothing deleted")
                    return .cancelled
                }
                Log.cleanup.error("Delete failed: \(error.localizedDescription, privacy: .public)")
                failures += plan.items.map { CleanupFailure(itemKey: $0.key, reason: error.localizedDescription) }
            }
        }

        // 2. Contacts, after a backup (FR-CON-4). A failure here never rolls back step 1.
        var backupURLs: [URL] = []
        var contactsChanged = 0
        if !plan.contactActions.isEmpty {
            if let contacts {
                let outcome = await contacts.apply(plan.contactActions)
                if let backup = outcome.backup { backupURLs.append(backup) }
                failures += outcome.failures
                contactsChanged = plan.contactActions.count - outcome.failures.count
            } else {
                failures += plan.contactActions.map {
                    CleanupFailure(itemKey: $0.key, reason: String(localized: "Contact changes aren't available."))
                }
            }
        }

        // 3. Calendar events, after an .ics backup. Independent of steps 1 and 2.
        var eventsDeleted = 0
        if !plan.calendarEvents.isEmpty {
            if let calendar {
                let outcome = await calendar.delete(plan.calendarEvents)
                if let backup = outcome.backup { backupURLs.append(backup) }
                failures += outcome.failures
                eventsDeleted = plan.calendarEvents.count - outcome.failures.count
            } else {
                failures += plan.calendarEvents.map {
                    CleanupFailure(itemKey: $0.key, reason: String(localized: "Calendar changes aren't available."))
                }
            }
        }

        var counts = Dictionary(grouping: deleted, by: \.category).mapValues(\.count)
        if contactsChanged > 0 { counts[.contacts] = contactsChanged }
        if eventsDeleted > 0 { counts[.calendar] = eventsDeleted }
        let bytes = deleted.reduce(Int64(0)) { $0 + $1.bytes }
        Log.cleanup.debug("Deleted \(deleted.count) assets, \(contactsChanged) contact actions, \(failures.count) failures, \(bytes) bytes")
        return CleanupResult(
            deletedAssetIDs: deleted.map(\.assetID),
            bytesFreed: bytes,
            countsByCategory: counts,
            failures: failures,
            backupURLs: backupURLs,
            wasCancelled: false
        )
    }
}
