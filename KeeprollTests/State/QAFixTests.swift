import Foundation
import Photos
import Testing
@testable import Keeproll

/// Regression tests for the build-4 QA report (docs/QA_REPORT.md).
@MainActor
struct QAFixTests {
    // MARK: H4 — contact groups and the cart

    private func contact(_ id: String, _ given: String, _ family: String, phone: String) -> ContactSummary {
        ContactSummary(id: id, givenName: given, familyName: family, organization: "", phones: [phone], emails: [], hasImage: false)
    }

    @Test func contactGroupIDsSurviveARescan() {
        let a = contact("A", "Kavya", "Nair", phone: "+91 98400 12345")
        let b = contact("B", "Kavya", "Nair", phone: "098400 12345")
        let first = ContactDeduplicator.groups([a, b])
        let second = ContactDeduplicator.groups([b, a]) // different fetch order
        #expect(first.count == 1)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(DuplicateContactGroup.stableID(memberIDs: ["A", "B"]) == DuplicateContactGroup.stableID(memberIDs: ["B", "A"]))
        #expect(DuplicateContactGroup.stableID(memberIDs: ["A", "B"]) != DuplicateContactGroup.stableID(memberIDs: ["A", "C"]))
    }

    @Test func staleContactChangesArePrunedAfterARescan() {
        let a = contact("A", "Kavya", "Nair", phone: "+91 98400 12345")
        let b = contact("B", "Kavya", "Nair", phone: "098400 12345")
        let group = ContactDeduplicator.groups([a, b])[0]
        let cart = CleanupCart()
        cart.add([
            .contactMerge(groupID: group.id, primaryID: "B", mergedIDs: ["A"], displayName: "Kavya Nair"),
            .asset(id: "p1", category: .similar, bytes: 10),
        ])

        // Same members: the merge stays.
        cart.pruneContacts(to: ContactDeduplicator.groups([a, b]))
        #expect(cart.containsMerge(groupID: group.id))

        // A third card joins the group: the old merge no longer describes it.
        let c = contact("C", "Kavya", "Nair", phone: "98400-12345")
        cart.pruneContacts(to: ContactDeduplicator.groups([a, b, c]))
        #expect(!cart.containsMerge(groupID: group.id))
        #expect(cart.contains(assetID: "p1"))

        // A delete for someone who's no longer a duplicate goes too.
        cart.add([.contactDelete(id: "A", displayName: "Kavya Nair")])
        cart.pruneContacts(to: [])
        #expect(!cart.contains(contactID: "A"))
        #expect(cart.count == 1)
    }

    @Test func actionsSharingAContactAreRefused() {
        let actions: [CleanupPlan.ContactAction] = [
            .merge(key: "merge:1", primaryID: "B", mergedIDs: ["A"]),
            .delete(key: "contact:A", id: "A"),
            .delete(key: "contact:Z", id: "Z"),
        ]
        #expect(ContactsService.conflictingActionKeys(actions) == ["merge:1", "contact:A"])
    }

    // MARK: M1 — recommended never includes a Best

    private func photo(_ id: String) -> MediaItem {
        MediaItem(id: id, kind: .photo, creationDate: nil, pixelWidth: 4000, pixelHeight: 3000,
                  duration: nil, isFavorite: false, byteSize: 1_000)
    }

    @Test func recommendedSkipsEveryGroupsBestEvenWhenBlurry() {
        let group = SimilarGroup(id: UUID(), kind: .similar, members: [photo("best"), photo("b"), photo("c")], bestID: "best")
        let picks = DashboardViewModel.recommended(similar: [group], blurry: [photo("best"), photo("b"), photo("lone")])
        let ids = picks.map(\.0.id)
        #expect(!ids.contains("best"))
        #expect(Set(ids) == ["b", "c", "lone"])
        #expect(ids.count == 3) // "b" counted once
    }

    // MARK: L7 — backup text safety

    @Test func lineBreakLookalikesCantInjectFields() {
        let hostile = "Eve\rEMAIL:x@evil.test\u{2028}TEL:1\u{85}NOTE:y\u{2029}z\u{0B}"
        let escaped = BackupText.escape(hostile)
        for scalar in ["\r", "\n", "\u{2028}", "\u{2029}", "\u{85}", "\u{0B}"] {
            #expect(!escaped.contains(scalar))
        }
        #expect(escaped == #"Eve\nEMAIL:x@evil.test\nTEL:1\nNOTE:y\nz\n"#)
        #expect(BackupText.normalized("a\r\nb") == "a\nb")
    }

    @Test func vCardLinesAreFoldedAndIncludeThePhotoAndNewFields() {
        var card = VCardWriter.Card()
        card.givenName = "Priya"
        card.familyName = String(repeating: "R", count: 120)
        card.department = "Research"
        card.organization = "Meridian"
        card.socialProfiles = [("Twitter", "priya", "")]
        card.relations = [("Sister", "Anu")]
        card.dates = [("Anniversary", DateComponents(year: 2020, month: 2, day: 14))]
        card.photoJPEG = Data(repeating: 0xAB, count: 300)
        let text = VCardWriter.card(card)
        for line in text.components(separatedBy: "\r\n") {
            #expect(line.utf8.count <= 75)
        }
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
        #expect(unfolded.contains("ORG:Meridian;Research\r\n"))
        #expect(unfolded.contains("X-SOCIALPROFILE;TYPE=TWITTER:x-apple:priya\r\n"))
        #expect(unfolded.contains("item1.X-ABRELATEDNAMES:Anu\r\nitem1.X-ABLabel:Sister\r\n"))
        #expect(unfolded.contains("item2.X-ABDATE:2020-02-14\r\n"))
        #expect(unfolded.contains("PHOTO;ENCODING=b;TYPE=JPEG:" + Data(repeating: 0xAB, count: 300).base64EncodedString() + "\r\n"))
    }

    @Test func foldingNeverSplitsAMultibyteCharacter() {
        let line = "SUMMARY:" + String(repeating: "த", count: 60) // 3 bytes each
        let folded = BackupText.fold(line)
        for part in folded.components(separatedBy: "\r\n") { #expect(part.utf8.count <= 75) }
        #expect(folded.replacingOccurrences(of: "\r\n ", with: "") == line)
    }

    // MARK: L6 — all-day end dates are exclusive

    @Test func allDayEndIsTheDayAfter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let lastMoment = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23, minute: 59, second: 59))!
        let sixth = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6))!
        #expect(ICSWriter.allDayEnd(start: start, end: lastMoment, calendar: calendar) == sixth)
        // Already exclusive (midnight after): unchanged, not pushed a further day.
        #expect(ICSWriter.allDayEnd(start: start, end: sixth, calendar: calendar) == sixth)
        // End equal to start: still at least one day.
        #expect(ICSWriter.allDayEnd(start: start, end: start, calendar: calendar) == sixth)
    }

    @Test func icsBackupKeepsAlarms() {
        let event = ICSWriter.Event(uid: "u1", title: "Dentist", start: Date(timeIntervalSince1970: 0),
                                    end: Date(timeIntervalSince1970: 3600), isAllDay: false,
                                    alarms: [.relative(-900)])
        let text = ICSWriter.document([event])
        #expect(text.contains("BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Dentist\r\nTRIGGER:-PT900S\r\nEND:VALARM\r\n"))
    }

    // MARK: M5 — duplicates only within one calendar

    @Test func copiesInDifferentCalendarsAreNotDuplicates() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func event(_ id: String, calendar: String) -> CalendarEventSummary {
            CalendarEventSummary(id: id, title: "Standup", start: start, end: start.addingTimeInterval(900),
                                 calendarTitle: calendar, isAllDay: false, calendarID: calendar)
        }
        let findings = CalendarCleanupFinder.find([event("1", calendar: "work"), event("2", calendar: "shared")],
                                                  now: start.addingTimeInterval(86_400))
        #expect(findings.duplicateGroups.isEmpty)
        let same = CalendarCleanupFinder.find([event("1", calendar: "work"), event("2", calendar: "work")],
                                              now: start.addingTimeInterval(86_400))
        #expect(same.duplicateGroups.count == 1)
    }

    // MARK: L8 — corrupt cache lengths

    @Test func binaryReaderRejectsLengthsTheFileCantHold() {
        var writer = BinaryWriter()
        writer.append([Float(1), Float(2)])
        var reader = BinaryReader(data: writer.data)
        #expect(reader.readFloats(1_000_000_000) == nil)
        #expect(reader.readFloats(-1) == nil)
        #expect(reader.readFloats(2) == [1, 2])
    }

    // MARK: L11 — unique diagnostics names

    @Test func diagnosticsNamesDontCollideWithinASecond() {
        let now = Date()
        let a = DiagnosticsService.fileName(kind: "metrics", date: now)
        let b = DiagnosticsService.fileName(kind: "metrics", date: now)
        #expect(a != b)
        #expect(a.hasPrefix("metrics-") && a.hasSuffix(".json"))
    }

    // MARK: M3 — originals the vault can't fully hold stay in the library

    @Test func rawAndEditedOriginalsAreNotQueued() {
        #expect(!VaultStore.hasExtraOriginals(types: [.photo]))
        #expect(!VaultStore.hasExtraOriginals(types: [.photo, .pairedVideo]))
        #expect(VaultStore.hasExtraOriginals(types: [.photo, .alternatePhoto]))
        #expect(VaultStore.hasExtraOriginals(types: [.photo, .fullSizePhoto, .adjustmentData]))
    }

    @Test func oldVaultIndexesStillDecode() throws {
        let json = #"[{"id":"7C2E3F43-9C59-4D7B-9A43-55B1A2D3E4F5","kind":"photo","fileName":"a.jpg","thumbnailName":"a-t.jpg","addedAt":0,"bytes":10}]"#
        let items = try JSONDecoder().decode([VaultItem].self, from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].pairedFileName == nil)
    }

    // MARK: H2 — locking closes an open vault item

    @Test func lockingClosesTheOpenItem() async {
        let store = FakeVaultStore()
        _ = await store.importAssets(["a"]) { _, _ in }
        let vm = VaultViewModel(store: store, auth: FakeAuth(result: .unlocked), cart: CleanupCart(), router: AppRouter())
        await vm.unlock()
        vm.opened = vm.items.first
        #expect(vm.opened != nil)
        vm.lockNow()
        #expect(vm.opened == nil)
        #expect(vm.items.isEmpty)
    }

    // MARK: M2 — backups expire

    @Test func backupsOlderThanTheRetentionAreDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("contacts-old.vcf")
        let fresh = dir.appendingPathComponent("calendar-new.ics")
        let other = dir.appendingPathComponent("notes.txt")
        for url in [old, fresh, other] { try Data("x".utf8).write(to: url) }
        let longAgo = Date().addingTimeInterval(-100 * 86_400)
        try FileManager.default.setAttributes([.creationDate: longAgo, .modificationDate: longAgo], ofItemAtPath: old.path)

        #expect(BackupStore.files(in: dir).count == 2) // the .txt isn't a backup
        #expect(BackupStore.prune(in: dir) == 1)
        #expect(BackupStore.files(in: dir).map(\.url.lastPathComponent) == ["calendar-new.ics"])
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    // MARK: UX review P2-3 — backups say what they hold

    @Test func backupCountsTheEventsAndContactsInside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ics = dir.appendingPathComponent("calendar-a.ics")
        try Data("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:A\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nSUMMARY:B\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n".utf8).write(to: ics)
        let empty = dir.appendingPathComponent("calendar-b.ics")
        try Data("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n".utf8).write(to: empty)
        let vcf = dir.appendingPathComponent("contacts-c.vcf")
        try Data("BEGIN:VCARD\nFN:A\nEND:VCARD\n".utf8).write(to: vcf)

        let counts = Dictionary(uniqueKeysWithValues: BackupStore.files(in: dir).map { ($0.url.lastPathComponent, $0.itemCount) })
        #expect(counts == ["calendar-a.ics": 2, "calendar-b.ics": 0, "contacts-c.vcf": 1])
    }

    // MARK: Security review — calendar cart and alarm guard

    @Test func calendarRemovalsNoLongerSuggestedArePruned() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func event(_ id: String) -> CalendarEventSummary {
            CalendarEventSummary(id: id, title: "Standup", start: start, end: start.addingTimeInterval(900),
                                 calendarTitle: "Work", isAllDay: false, calendarID: "work")
        }
        let cart = CleanupCart()
        cart.add([.calendarEvent(id: "B", title: "Standup", start: start), .asset(id: "p", category: .similar, bytes: 1)])
        // B is still the extra copy of A: kept in the cart.
        cart.pruneCalendar(to: CalendarFindings(duplicateGroups: [[event("A"), event("B")]], oldEvents: []))
        #expect(cart.count == 2)
        // A was deleted elsewhere, so B is the only copy now and leaves the cart.
        cart.pruneCalendar(to: CalendarFindings())
        #expect(cart.count == 1)
        #expect(cart.contains(assetID: "p"))
    }

    @Test func impossibleAlarmOffsetsAreSkippedNotCrashed() {
        #expect(ICSWriter.trigger(for: .relative(.nan)) == nil)
        #expect(ICSWriter.trigger(for: .relative(.infinity)) == nil)
        #expect(ICSWriter.trigger(for: .relative(1e19)) == nil)
        #expect(ICSWriter.trigger(for: .relative(-600)) == "TRIGGER:-PT600S")
        let event = ICSWriter.Event(uid: "u", title: "T", start: Date(timeIntervalSince1970: 0),
                                    end: Date(timeIntervalSince1970: 60), isAllDay: false, alarms: [.relative(.nan)])
        #expect(!ICSWriter.document([event]).contains("VALARM"))
    }

    @Test func privacyManifestDeclaresFileTimestamps() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        #expect(text.contains("C617.1"))
    }
}
