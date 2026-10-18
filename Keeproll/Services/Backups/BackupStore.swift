import Foundation

/// One backup file written before a contacts or calendar change.
nonisolated struct BackupFile: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case contacts, calendar }

    let url: URL
    let kind: Kind
    let date: Date
    let bytes: Int64

    var id: URL { url }
}

/// Lists, deletes and expires the backups in `Application Support/Backups` (QA M2).
/// They used to be reachable only from the Summary screen and were never deleted.
nonisolated enum BackupStore {
    /// Backups are kept this long, then removed at launch.
    static let retentionDays = 90

    static var directory: URL { ContactsService.defaultBackupDirectory }

    /// Newest first. Only files Keeproll wrote (`contacts-*.vcf`, `calendar-*.ics`).
    static func files(in directory: URL = BackupStore.directory) -> [BackupFile] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url -> BackupFile? in
            let name = url.lastPathComponent
            let kind: BackupFile.Kind
            if name.hasPrefix("contacts-") && url.pathExtension == "vcf" { kind = .contacts }
            else if name.hasPrefix("calendar-") && url.pathExtension == "ics" { kind = .calendar }
            else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            return BackupFile(url: url, kind: kind, date: date, bytes: Int64(values?.fileSize ?? 0))
        }
        .sorted { $0.date > $1.date }
    }

    @discardableResult
    static func delete(_ file: BackupFile) -> Bool {
        do {
            try FileManager.default.removeItem(at: file.url)
            Log.ui.debug("Deleted backup \(file.url.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Log.ui.error("Backup delete failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Removes backups older than the retention period. Returns how many were removed.
    @discardableResult
    static func prune(in directory: URL = BackupStore.directory, now: Date = Date(), days: Int = BackupStore.retentionDays) -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let expired = files(in: directory).filter { $0.date < cutoff }
        let removed = expired.filter(delete).count
        if removed > 0 { Log.ui.debug("Pruned \(removed) expired backups") }
        return removed
    }
}
