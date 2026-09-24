import Photos

/// What changed in the photo library since the last notification.
nonisolated struct LibraryDelta: Sendable, Equatable {
    /// Assets that no longer exist (deleted in Photos, or by Sift itself).
    var removedIDs: Set<String> = []
    /// Something was added or edited, so scan results may be out of date.
    var hasAdditionsOrEdits = false

    var isEmpty: Bool { removedIDs.isEmpty && !hasAdditionsOrEdits }
}

nonisolated protocol LibraryChangeMonitoring: Sendable {
    /// Starts watching. `onChange` is called on the main actor with each non-empty delta.
    func start(onChange: @escaping @MainActor @Sendable (LibraryDelta) -> Void)
}

/// Watches the photo library (ARCHITECTURE §6.4).
///
/// PhotoKit describes changes as a diff against a fetch result you hold, so this keeps
/// one lazy fetch of every image and video and asks `changeDetails(for:)` for exact
/// removed / inserted / changed lists. No re-querying the library on every change.
///
/// `@unchecked Sendable`: `allAssets` and `handler` are only touched under `lock`
/// (PhotoKit calls `photoLibraryDidChange` on a background queue).
nonisolated final class LibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, LibraryChangeMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var allAssets: PHFetchResult<PHAsset>?
    private var handler: (@MainActor @Sendable (LibraryDelta) -> Void)?

    func start(onChange: @escaping @MainActor @Sendable (LibraryDelta) -> Void) {
        let alreadyStarted: Bool = lock.withLock {
            handler = onChange
            guard allAssets == nil else { return true }
            allAssets = PHAsset.fetchAssets(with: nil) // lazy: no objects are loaded here
            return false
        }
        if !alreadyStarted {
            PHPhotoLibrary.shared().register(self)
            Log.photos.debug("Library change monitor started")
        }
    }

    func photoLibraryDidChange(_ change: PHChange) {
        let result: (LibraryDelta, (@MainActor @Sendable (LibraryDelta) -> Void)?)? = lock.withLock {
            guard let current = allAssets, let details = change.changeDetails(for: current) else { return nil }
            allAssets = details.fetchResultAfterChanges
            var delta = LibraryDelta()
            delta.removedIDs = Set(details.removedObjects.map(\.localIdentifier))
            delta.hasAdditionsOrEdits = !details.insertedObjects.isEmpty || !details.changedObjects.isEmpty
            return (delta, handler)
        }
        guard let (delta, handler) = result, !delta.isEmpty, let handler else { return }
        Log.photos.debug("Library changed: \(delta.removedIDs.count) removed, additions/edits: \(delta.hasAdditionsOrEdits)")
        Task { @MainActor in handler(delta) }
    }
}
