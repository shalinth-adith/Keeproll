import Foundation
import Observation

@Observable
final class DuplicateContactsViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart
    /// Chosen primary per group; defaults to the most complete contact.
    private var primaries: [UUID: String] = [:]

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    var groups: [DuplicateContactGroup] { scanStore.contacts.value ?? [] }
    var isLoading: Bool { scanStore.contacts.isLoading }
    var permission: PermissionState { scanStore.contactsPermission }
    var duplicateCount: Int { scanStore.duplicateContactCount }
    var queuedMerges: Int { groups.filter { cart.containsMerge(groupID: $0.id) }.count }
    var queuedDeletes: Int { groups.flatMap(\.contacts).filter { cart.contains(contactID: $0.id) }.count }

    func primaryID(for group: DuplicateContactGroup) -> String {
        primaries[group.id] ?? group.suggestedPrimaryID
    }

    func setPrimary(_ id: String, for group: DuplicateContactGroup) {
        primaries[group.id] = id
        // The primary is kept; it can't also be queued for deletion.
        cart.remove(key: "contact:\(id)")
    }

    func selectedForDeletion(in group: DuplicateContactGroup) -> Set<String> {
        Set(group.contacts.map(\.id).filter { cart.contains(contactID: $0) })
    }

    func mergeQueued(for group: DuplicateContactGroup) -> Bool { cart.containsMerge(groupID: group.id) }

    func toggleDelete(_ id: String, in group: DuplicateContactGroup) {
        guard let contact = group.contacts.first(where: { $0.id == id }) else { return }
        cart.toggle(.contactDelete(id: id, displayName: contact.displayName))
    }

    /// Queue a merge for the group. Clears any individual deletes inside it, because the
    /// merge already removes the non-primary contacts.
    func toggleMerge(for group: DuplicateContactGroup) {
        let primary = primaryID(for: group)
        if mergeQueued(for: group) {
            cart.remove(key: "merge:\(group.id.uuidString)")
        } else {
            for contact in group.contacts { cart.remove(key: "contact:\(contact.id)") }
            let merged = group.mergedPreview(primaryID: primary)
            cart.add([.contactMerge(groupID: group.id, primaryID: primary,
                                    mergedIDs: group.contacts.map(\.id).filter { $0 != primary },
                                    displayName: merged.displayName)])
        }
    }

    /// Queue a merge for every group (the safe bulk action: nothing is lost in a merge).
    func mergeAll() {
        for group in groups where !mergeQueued(for: group) { toggleMerge(for: group) }
    }

    func requestAccess() async {
        if permission == .notDetermined {
            await scanStore.requestContacts()
            scanStore.scan()
        } else {
            SystemActions.openSettings()
        }
    }
}
