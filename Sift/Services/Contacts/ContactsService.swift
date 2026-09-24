import Contacts

/// Reads contacts, finds duplicates, and applies approved merges/deletes.
///
/// Holds no state: a fresh `CNContactStore` is made per call (it isn't Sendable).
/// Mutations only arrive through `DeletionService` with a Review-approved plan (D10),
/// and every mutation is preceded by a vCard backup (D11).
nonisolated final class ContactsService: ContactsScanning, ContactsMutating {
    /// Never includes `CNContactNoteKey`, which needs a special entitlement (D11).
    private static var summaryKeys: [CNKeyDescriptor] { [
        CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactImageDataAvailableKey,
    ] as [CNKeyDescriptor] }

    private static var fullKeys: [CNKeyDescriptor] { summaryKeys + ([
        CNContactMiddleNameKey, CNContactNamePrefixKey, CNContactNameSuffixKey, CNContactNicknameKey,
        CNContactJobTitleKey, CNContactPostalAddressesKey, CNContactUrlAddressesKey, CNContactBirthdayKey,
        CNContactImageDataKey,
    ] as [CNKeyDescriptor]) }

    private let backupDirectory: URL

    init(backupDirectory: URL = ContactsService.defaultBackupDirectory) {
        self.backupDirectory = backupDirectory
    }

    nonisolated static var defaultBackupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Backups")
    }

    // MARK: - Scanning

    @concurrent
    func findDuplicates() async -> [DuplicateContactGroup] {
        let signpost = Signposts.scan.beginInterval("scan.contacts")
        defer { Signposts.scan.endInterval("scan.contacts", signpost) }

        let request = CNContactFetchRequest(keysToFetch: Self.summaryKeys)
        request.unifyResults = true
        var summaries: [ContactSummary] = []
        do {
            try CNContactStore().enumerateContacts(with: request) { contact, _ in
                summaries.append(ContactSummary(
                    id: contact.identifier,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    organization: contact.organizationName,
                    phones: contact.phoneNumbers.map(\.value.stringValue),
                    emails: contact.emailAddresses.map { $0.value as String },
                    hasImage: contact.imageDataAvailable
                ))
            }
        } catch {
            Log.contacts.error("Contacts fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let groups = ContactDeduplicator.groups(summaries)
        Log.contacts.debug("Scanned \(summaries.count) contacts, \(groups.count) duplicate groups")
        return groups
    }

    // MARK: - Mutations (only via DeletionService)

    @concurrent
    func apply(_ actions: [CleanupPlan.ContactAction]) async -> (backup: URL?, failures: [CleanupFailure]) {
        let store = CNContactStore()
        let ids = Array(Set(actions.flatMap(\.affectedIDs)))
        let contacts: [String: CNContact]
        do {
            let fetched = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: ids), keysToFetch: Self.fullKeys)
            contacts = Dictionary(fetched.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            return (nil, actions.map { CleanupFailure(itemKey: $0.key, reason: error.localizedDescription) })
        }

        // 1. Backup first. If it can't be written, change nothing.
        let backupURL: URL
        do {
            backupURL = try writeBackup(ids.compactMap { contacts[$0] })
        } catch {
            Log.contacts.error("Backup failed, no contact changes made: \(error.localizedDescription, privacy: .public)")
            let reason = String(localized: "Couldn't save a backup first, so nothing was changed.")
            return (nil, actions.map { CleanupFailure(itemKey: $0.key, reason: reason) })
        }

        // 2. One save request per action, so one read-only account can't block the rest (FR-CON-5).
        var failures: [CleanupFailure] = []
        for action in actions {
            let request = CNSaveRequest()
            switch action {
            case .merge(_, let primaryID, let mergedIDs):
                guard let primary = contacts[primaryID]?.mutableCopy() as? CNMutableContact else {
                    failures.append(.init(itemKey: action.key, reason: String(localized: "This contact no longer exists.")))
                    continue
                }
                let others = mergedIDs.compactMap { contacts[$0] }
                Self.merge(others, into: primary)
                request.update(primary)
                for other in others {
                    if let mutable = other.mutableCopy() as? CNMutableContact { request.delete(mutable) }
                }
            case .delete(_, let id):
                guard let mutable = contacts[id]?.mutableCopy() as? CNMutableContact else {
                    failures.append(.init(itemKey: action.key, reason: String(localized: "This contact no longer exists.")))
                    continue
                }
                request.delete(mutable)
            }
            do {
                try store.execute(request)
            } catch {
                Log.contacts.error("Contact change failed: \(error.localizedDescription, privacy: .public)")
                failures.append(.init(itemKey: action.key, reason: String(localized: "This contact's account doesn't allow changes.")))
            }
        }
        Log.contacts.debug("Applied \(actions.count - failures.count) of \(actions.count) contact actions")
        return (backupURL, failures)
    }

    /// Copies every value the primary is missing from the others (FR-CON-2).
    static func merge(_ others: [CNContact], into primary: CNMutableContact) {
        for other in others {
            if primary.givenName.isEmpty { primary.givenName = other.givenName }
            if primary.familyName.isEmpty { primary.familyName = other.familyName }
            if primary.middleName.isEmpty { primary.middleName = other.middleName }
            if primary.nickname.isEmpty { primary.nickname = other.nickname }
            if primary.organizationName.isEmpty { primary.organizationName = other.organizationName }
            if primary.jobTitle.isEmpty { primary.jobTitle = other.jobTitle }
            if primary.birthday == nil { primary.birthday = other.birthday }
            if primary.imageData == nil, let image = other.imageData { primary.imageData = image }

            let phoneKeys = Set(primary.phoneNumbers.compactMap { ContactNormalizer.phoneKey($0.value.stringValue) })
            primary.phoneNumbers += other.phoneNumbers.filter { value in
                guard let key = ContactNormalizer.phoneKey(value.value.stringValue) else { return false }
                return !phoneKeys.contains(key)
            }
            let emailKeys = Set(primary.emailAddresses.compactMap { ContactNormalizer.emailKey($0.value as String) })
            primary.emailAddresses += other.emailAddresses.filter { value in
                guard let key = ContactNormalizer.emailKey(value.value as String) else { return false }
                return !emailKeys.contains(key)
            }
            let formatter = CNPostalAddressFormatter()
            let addresses = Set(primary.postalAddresses.map { formatter.string(from: $0.value).lowercased() })
            primary.postalAddresses += other.postalAddresses.filter { !addresses.contains(formatter.string(from: $0.value).lowercased()) }
            let urls = Set(primary.urlAddresses.map { ($0.value as String).lowercased() })
            primary.urlAddresses += other.urlAddresses.filter { !urls.contains(($0.value as String).lowercased()) }
        }
    }

    private func writeBackup(_ contacts: [CNContact]) throws -> URL {
        let cards = contacts.map { c in
            VCardWriter.Card(
                givenName: c.givenName, familyName: c.familyName, middleName: c.middleName,
                prefix: c.namePrefix, suffix: c.nameSuffix, nickname: c.nickname,
                organization: c.organizationName, jobTitle: c.jobTitle,
                phones: c.phoneNumbers.map { ($0.label ?? "", $0.value.stringValue) },
                emails: c.emailAddresses.map { ($0.label ?? "", $0.value as String) },
                urls: c.urlAddresses.map { $0.value as String },
                addresses: c.postalAddresses.map { ($0.label ?? "", $0.value.street, $0.value.city, $0.value.state, $0.value.postalCode, $0.value.country) },
                birthday: c.birthday
            )
        }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDirectory.appendingPathComponent("contacts-\(stamp).vcf")
        try Data(VCardWriter.document(cards).utf8).write(to: url, options: [.atomic, .completeFileProtection])
        Log.contacts.debug("Backed up \(cards.count) contacts before changes")
        return url
    }
}
