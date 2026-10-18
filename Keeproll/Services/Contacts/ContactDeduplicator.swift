import Foundation

/// Match keys for contacts. Two contacts that share any key are candidates for the same
/// person (FR-CON-1).
nonisolated enum ContactNormalizer {
    /// Lower-cased, accent-folded name tokens, sorted so "Kavya Nair" == "Nair Kavya".
    /// Needs at least two tokens: a lone "Mom" or "Office" is too weak to call a duplicate.
    static func nameKey(given: String, family: String) -> String? {
        let folded = "\(given) \(family)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let tokens = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard tokens.count >= 2 else { return nil }
        return tokens.sorted().joined(separator: " ")
    }

    /// Last 10 digits, so "+91 98400 12345", "098400 12345" and "98400-12345" match.
    /// Needs at least 7 digits to rule out short codes.
    static func phoneKey(_ raw: String) -> String? {
        let digits = raw.unicodeScalars.filter { $0.properties.numericType == .decimal }.map { Character($0) }
        guard digits.count >= 7 else { return nil }
        return String(digits.suffix(10))
    }

    static func emailKey(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.contains("@") ? email : nil
    }
}

nonisolated enum ContactDeduplicator {
    /// Groups contacts that share a phone number, email, or full name. Pure and
    /// deterministic, so it's unit-tested without a contact store.
    static func groups(_ contacts: [ContactSummary]) -> [DuplicateContactGroup] {
        var sets = UnionFind()
        var owner: [String: Int] = [:]
        var keysByContact: [[String]] = []

        for (index, contact) in contacts.enumerated() {
            sets.add()
            var keys: [String] = []
            keys += contact.phones.compactMap(ContactNormalizer.phoneKey).map { "p:\($0)" }
            keys += contact.emails.compactMap(ContactNormalizer.emailKey).map { "e:\($0)" }
            if let name = ContactNormalizer.nameKey(given: contact.givenName, family: contact.familyName) {
                keys.append("n:\(name)")
            }
            keys = Array(Set(keys))
            keysByContact.append(keys)
            for key in keys {
                if let other = owner[key] { sets.union(index, other) } else { owner[key] = index }
            }
        }

        var members: [Int: [Int]] = [:]
        for index in contacts.indices { members[sets.find(index), default: []].append(index) }

        return members.values
            .filter { $0.count > 1 }
            .map { indices -> DuplicateContactGroup in
                // A reason applies if at least two members share a key of that kind.
                var counts: [String: Int] = [:]
                for index in indices { for key in keysByContact[index] { counts[key, default: 0] += 1 } }
                let shared = counts.filter { $0.value > 1 }.keys
                var reasons: [MatchReason] = []
                if shared.contains(where: { $0.hasPrefix("p:") }) { reasons.append(.samePhone) }
                if shared.contains(where: { $0.hasPrefix("e:") }) { reasons.append(.sameEmail) }
                if shared.contains(where: { $0.hasPrefix("n:") }) { reasons.append(.sameName) }
                let members = indices.map { contacts[$0] }
                return DuplicateContactGroup(id: DuplicateContactGroup.stableID(memberIDs: members.map(\.id)),
                                             contacts: members, reasons: reasons)
            }
            .sorted { $0.contacts[0].displayName.localizedCaseInsensitiveCompare($1.contacts[0].displayName) == .orderedAscending }
    }
}

/// Shared safety rules for the line-based backup formats (vCard and iCalendar).
nonisolated enum BackupText {
    /// Every character a reader might treat as a line break becomes `\n`, and other
    /// control characters are dropped. Without this, a contact name containing a lone
    /// `\r` or U+2028 could inject extra fields into a backup (QA L7).
    static func normalized(_ value: String) -> String {
        var out = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x0D:
                out.append("\n")
                previousWasCR = true
                continue
            case 0x0A:
                if !previousWasCR { out.append("\n") }
            case 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                out.append("\n")
            case 0x09:
                out.append(scalar)
            case 0x00..<0x20, 0x7F:
                break // other control characters
            default:
                out.append(scalar)
            }
            previousWasCR = false
        }
        return String(out)
    }

    /// Escapes a text value: backslash, comma, semicolon and newlines.
    static func escape(_ value: String) -> String {
        normalized(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 octets are folded with CRLF + space, never splitting a
    /// character (RFC 5545 §3.1, RFC 6350 §3.2).
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var out = ""
        out.reserveCapacity(line.utf8.count + line.utf8.count / 74 * 3)
        var count = 0
        for scalar in line.unicodeScalars {
            let size = String(scalar).utf8.count
            if count + size > 75 {
                out += "\r\n "
                count = 1
            }
            out.unicodeScalars.append(scalar)
            count += size
        }
        return out
    }
}

/// Minimal vCard 3.0 writer for the pre-change backup (FR-CON-4). Hand-written because
/// `CNContactVCardSerialization` wants keys (including notes) that need an entitlement.
nonisolated enum VCardWriter {
    nonisolated struct Card: Sendable, Equatable {
        var givenName = "", familyName = "", middleName = "", prefix = "", suffix = ""
        var nickname = "", organization = "", jobTitle = ""
        var phones: [(label: String, value: String)] = []
        var emails: [(label: String, value: String)] = []
        var urls: [String] = []
        var addresses: [(label: String, street: String, city: String, state: String, postalCode: String, country: String)] = []
        var birthday: DateComponents?
        var department = ""
        var phoneticGivenName = "", phoneticMiddleName = "", phoneticFamilyName = "", phoneticOrganization = ""
        var socialProfiles: [(service: String, username: String, url: String)] = []
        var instantMessages: [(service: String, username: String)] = []
        var relations: [(label: String, name: String)] = []
        var dates: [(label: String, date: DateComponents)] = []
        /// JPEG data of the contact photo, if any (QA H3).
        var photoJPEG: Data?

        static func == (a: Card, b: Card) -> Bool { VCardWriter.card(a) == VCardWriter.card(b) }
    }

    static func document(_ cards: [Card]) -> String {
        cards.map(card).joined()
    }

    static func card(_ c: Card) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:" + [c.familyName, c.givenName, c.middleName, c.prefix, c.suffix].map(escape).joined(separator: ";"))
        let full = [c.prefix, c.givenName, c.middleName, c.familyName, c.suffix].filter { !$0.isEmpty }.joined(separator: " ")
        lines.append("FN:" + escape(full.isEmpty ? (c.organization.isEmpty ? (c.phones.first?.value ?? "") : c.organization) : full))
        if !c.nickname.isEmpty { lines.append("NICKNAME:" + escape(c.nickname)) }
        if !c.phoneticGivenName.isEmpty { lines.append("X-PHONETIC-FIRST-NAME:" + escape(c.phoneticGivenName)) }
        if !c.phoneticMiddleName.isEmpty { lines.append("X-PHONETIC-MIDDLE-NAME:" + escape(c.phoneticMiddleName)) }
        if !c.phoneticFamilyName.isEmpty { lines.append("X-PHONETIC-LAST-NAME:" + escape(c.phoneticFamilyName)) }
        if !c.organization.isEmpty || !c.department.isEmpty {
            lines.append("ORG:" + escape(c.organization) + (c.department.isEmpty ? "" : ";" + escape(c.department)))
        }
        if !c.phoneticOrganization.isEmpty { lines.append("X-PHONETIC-ORG:" + escape(c.phoneticOrganization)) }
        if !c.jobTitle.isEmpty { lines.append("TITLE:" + escape(c.jobTitle)) }
        for phone in c.phones { lines.append("TEL;TYPE=\(type(phone.label)):" + escape(phone.value)) }
        for email in c.emails { lines.append("EMAIL;TYPE=INTERNET,\(type(email.label)):" + escape(email.value)) }
        for a in c.addresses {
            lines.append("ADR;TYPE=\(type(a.label)):;;" + [a.street, a.city, a.state, a.postalCode, a.country].map(escape).joined(separator: ";"))
        }
        for url in c.urls { lines.append("URL:" + escape(url)) }
        if let b = c.birthday, let date = date(b) { lines.append("BDAY:" + date) }
        for profile in c.socialProfiles {
            let value = profile.url.isEmpty ? "x-apple:" + escape(profile.username) : escape(profile.url)
            lines.append("X-SOCIALPROFILE;TYPE=\(type(profile.service)):" + value)
        }
        for im in c.instantMessages {
            lines.append("IMPP;X-SERVICE-TYPE=\(type(im.service)):x-apple:" + escape(im.username))
        }
        // Apple's grouped form keeps the label with the value.
        var group = 0
        for relation in c.relations {
            group += 1
            lines.append("item\(group).X-ABRELATEDNAMES:" + escape(relation.name))
            lines.append("item\(group).X-ABLabel:" + escape(relation.label))
        }
        for entry in c.dates {
            guard let date = date(entry.date) else { continue }
            group += 1
            lines.append("item\(group).X-ABDATE:" + date)
            lines.append("item\(group).X-ABLabel:" + escape(entry.label))
        }
        if let photo = c.photoJPEG, !photo.isEmpty {
            lines.append("PHOTO;ENCODING=b;TYPE=JPEG:" + photo.base64EncodedString())
        }
        lines.append("END:VCARD")
        return lines.map(BackupText.fold).joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ value: String) -> String { BackupText.escape(value) }

    private static func date(_ components: DateComponents) -> String? {
        guard let month = components.month, let day = components.day else { return nil }
        let year = components.year.map { String(format: "%04d", $0) } ?? "--"
        return "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
    }

    /// Maps Contacts labels like `_$!<Mobile>!$_` to vCard types.
    private static func type(_ label: String) -> String {
        let clean = label.replacingOccurrences(of: "_$!<", with: "").replacingOccurrences(of: ">!$_", with: "").uppercased()
        let allowed = clean.filter { $0.isASCII && $0.isLetter }
        return allowed.isEmpty ? "OTHER" : allowed
    }
}
