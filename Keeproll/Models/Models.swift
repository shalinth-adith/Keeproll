import Foundation
import SwiftUI

// Value types that cross actor boundaries. They carry identifiers, never PhotoKit or
// Contacts objects (those are not Sendable).

nonisolated enum CleanupCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
    case similar, screenshots, blurry, videos
    /// Images that arrived through messaging apps rather than the camera (bonus: smart categories).
    case chats
    /// Screenshots whose content has passed its use-by date: codes, passes, tickets (bonus: smart categories).
    case expired
    case contacts, calendar
    /// Originals of photos copied into the private vault. Never a dashboard card; it
    /// only appears on Review, so the user sees exactly what leaves the library.
    case vault
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .similar: "Similar Photos"
        case .screenshots: "Screenshots"
        case .blurry: "Blurry Photos"
        case .videos: "Large Videos"
        case .chats: "Saved from Chats"
        case .expired: "Expired Screenshots"
        case .contacts: "Duplicate Contacts"
        case .calendar: "Old Calendar Events"
        case .vault: "Moved to Vault"
        }
    }

    /// Short name for the dashboard card, so titles never wrap next to their number.
    var cardTitle: LocalizedStringResource {
        switch self {
        case .similar: "Similar"
        case .screenshots: "Screenshots"
        case .blurry: "Blurry"
        case .videos: "Videos"
        case .chats: "From chats"
        case .expired: "Expired"
        case .contacts: "Contacts"
        case .calendar: "Calendar"
        case .vault: "Vault"
        }
    }

    var symbol: String {
        switch self {
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .blurry: "camera.metering.unknown"
        case .videos: "video"
        case .chats: "bubble.left.and.bubble.right"
        case .expired: "clock.badge.xmark"
        case .contacts: "person.2"
        case .calendar: "calendar"
        case .vault: "lock.shield"
        }
    }

    @MainActor var color: Color {
        switch self {
        case .similar: Color.keeproll.catSimilar
        case .screenshots: Color.keeproll.catScreenshots
        case .blurry: Color.keeproll.catBlurry
        case .videos: Color.keeproll.catVideos
        case .chats: Color.keeproll.catChats
        case .expired: Color.keeproll.catExpired
        case .contacts: Color.keeproll.catContacts
        case .calendar: Color.keeproll.catCalendar
        case .vault: Color.keeproll.catVault
        }
    }
}

nonisolated struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case photo, screenshot, video }

    /// `PHAsset.localIdentifier`.
    let id: String
    let kind: Kind
    let creationDate: Date?
    var modificationDate: Date? = nil
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval?
    let isFavorite: Bool
    /// Filled in by `AssetSizeService`; nil until known.
    var byteSize: Int64?
    /// True when the size is a pixel-count estimate rather than the real file size.
    var sizeIsEstimated: Bool = false
    /// The original is in iCloud and not on this device (FR-SIM-7).
    var isCloudOnly: Bool = false
}

/// A set of duplicate or near-identical photos. Members are ordered best first.
nonisolated struct SimilarGroup: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case exactDuplicate, similar }

    let id: UUID
    let kind: Kind
    var members: [MediaItem]
    var bestID: String

    var date: Date? { members.compactMap(\.creationDate).min() }
    var totalBytes: Int64 { members.reduce(0) { $0 + ($1.byteSize ?? 0) } }
    /// Everything except the best shot.
    var freeableBytes: Int64 { totalBytes - (members.first { $0.id == bestID }?.byteSize ?? 0) }
    var othersThanBest: [MediaItem] { members.filter { $0.id != bestID } }
}

/// What the similarity scan reports while it runs. Groups are identified by `id`; a
/// later `.upsert` with the same id replaces the earlier one (groups grow as the scan
/// finds more members), and `.remove` drops a group that merged into another.
nonisolated enum SimilarityEvent: Sendable {
    case progress(processed: Int, total: Int)
    case upsert(SimilarGroup)
    case remove(UUID)
    case blurry([MediaItem])
    #if DEBUG
    case calibration(CalibrationData)
    #endif
}

nonisolated struct ContactSummary: Identifiable, Hashable, Sendable {
    /// `CNContact.identifier`.
    let id: String
    var givenName: String
    var familyName: String
    var organization: String
    var phones: [String]
    var emails: [String]
    var hasImage: Bool

    var displayName: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { return name }
        if !organization.isEmpty { return organization }
        return phones.first ?? emails.first ?? String(localized: "No name")
    }

    var initials: String {
        let parts = [givenName, familyName].filter { !$0.isEmpty }
        let letters = parts.compactMap(\.first).prefix(2)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// How many fields carry data; the fullest contact is the default primary.
    var completeness: Int {
        [givenName, familyName, organization].filter { !$0.isEmpty }.count + phones.count + emails.count + (hasImage ? 1 : 0)
    }
}

nonisolated enum MatchReason: Hashable, Sendable {
    case samePhone, sameEmail, sameName

    var label: LocalizedStringResource {
        switch self {
        case .samePhone: "Same number"
        case .sameEmail: "Same email"
        case .sameName: "Same name"
        }
    }

    var symbol: String {
        switch self {
        case .samePhone: "phone"
        case .sameEmail: "envelope"
        case .sameName: "person.text.rectangle"
        }
    }
}

nonisolated struct DuplicateContactGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var contacts: [ContactSummary]
    var reasons: [MatchReason]

    var suggestedPrimaryID: String {
        contacts.max { $0.completeness < $1.completeness }?.id ?? contacts[0].id
    }

    /// The union of every field, with the primary's name kept.
    func mergedPreview(primaryID: String) -> ContactSummary {
        guard var merged = contacts.first(where: { $0.id == primaryID }) ?? contacts.first else {
            return ContactSummary(id: "", givenName: "", familyName: "", organization: "", phones: [], emails: [], hasImage: false)
        }
        for contact in contacts where contact.id != merged.id {
            if merged.givenName.isEmpty { merged.givenName = contact.givenName }
            if merged.familyName.isEmpty { merged.familyName = contact.familyName }
            if merged.organization.isEmpty { merged.organization = contact.organization }
            for phone in contact.phones where !merged.phones.contains(where: { Self.samePhone($0, phone) }) { merged.phones.append(phone) }
            for email in contact.emails where !merged.emails.contains(where: { Self.sameEmail($0, email) }) { merged.emails.append(email) }
            merged.hasImage = merged.hasImage || contact.hasImage
        }
        return merged
    }

    /// Same number if the last 10 digits match (drops country code and formatting).
    static func samePhone(_ a: String, _ b: String) -> Bool {
        let da = a.filter(\.isNumber).suffix(10), db = b.filter(\.isNumber).suffix(10)
        return !da.isEmpty && da == db
    }

    static func sameEmail(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).lowercased() == b.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

nonisolated enum PermissionState: Hashable, Sendable {
    case notDetermined, denied, restricted, limited, authorized

    /// The app may read (some or all of) the data.
    var canRead: Bool { self == .authorized || self == .limited }
}

nonisolated enum PermissionKind: Hashable, Sendable { case photos, contacts }

nonisolated struct StorageSnapshot: Hashable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

/// An item waiting in the cleanup cart. Assets are keyed by their identifier, so the
/// same photo selected from two categories is counted once (FR-CART-2).
nonisolated enum CartItem: Hashable, Sendable {
    case asset(id: String, category: CleanupCategory, bytes: Int64)
    case contactMerge(groupID: UUID, primaryID: String, mergedIDs: [String], displayName: String)
    case contactDelete(id: String, displayName: String)
    case calendarEvent(id: String, title: String, start: Date?)

    var key: String {
        switch self {
        case .asset(let id, _, _): "asset:\(id)"
        case .contactMerge(let groupID, _, _, _): "merge:\(groupID.uuidString)"
        case .contactDelete(let id, _): "contact:\(id)"
        case .calendarEvent(let id, _, _): "event:\(id)"
        }
    }

    var category: CleanupCategory {
        switch self {
        case .asset(_, let category, _): category
        case .contactMerge, .contactDelete: .contacts
        case .calendarEvent: .calendar
        }
    }

    var bytes: Int64 {
        switch self {
        case .asset(_, _, let bytes): bytes
        case .contactMerge, .contactDelete, .calendarEvent: 0
        }
    }
}

nonisolated struct CleanupFailure: Hashable, Sendable {
    let itemKey: String
    let reason: String
}

nonisolated struct CleanupResult: Hashable, Sendable {
    let deletedAssetIDs: [String]
    let bytesFreed: Int64
    let countsByCategory: [CleanupCategory: Int]
    let failures: [CleanupFailure]
    /// Backups written before contacts or calendar events were changed (.vcf, .ics).
    var backupURLs: [URL] = []
    /// The user dismissed the iOS confirmation; nothing was deleted.
    let wasCancelled: Bool

    static let cancelled = CleanupResult(deletedAssetIDs: [], bytesFreed: 0, countsByCategory: [:], failures: [], wasCancelled: true)
}

nonisolated enum AppError: LocalizedError, Hashable, Sendable {
    case permissionDenied(PermissionKind)
    case photoLibrary(String)
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied(.photos): String(localized: "Keeproll doesn't have access to your photos.")
        case .permissionDenied(.contacts): String(localized: "Keeproll doesn't have access to your contacts.")
        case .photoLibrary: String(localized: "Something went wrong reading your photo library. Please try again.")
        case .storageUnavailable: String(localized: "Couldn't read this iPhone's storage.")
        }
    }
}

// MARK: - Smart categories (bonus)

/// What can be known about where an image came from, without decoding it. Inputs to
/// `ProvenanceEngine`; gathered by `ChatMediaScanner` from PhotoKit and a header read.
nonisolated struct AssetProvenance: Sendable, Equatable {
    var originalFilename: String?
    /// Uniform type identifier of the original resource, e.g. "public.jpeg".
    var uniformType: String?
    var pixelWidth: Int
    var pixelHeight: Int
    /// The file header carries camera make/model or lens/exposure data. nil = not readable
    /// (for example the original is only in iCloud).
    var hasCameraMetadata: Bool?
    var hasLocation: Bool
    var isFavorite: Bool
    /// iOS 18 Vision aesthetics: the content is a "utility" image (screens, documents,
    /// forwards) rather than a memorable photo. nil = not evaluated.
    var isUtility: Bool?
}

/// The engine's opinion that an image was saved from a chat app.
nonisolated struct ChatSavedVerdict: Sendable, Hashable {
    enum Source: String, Sendable, Hashable { case whatsapp, telegram, unknownApp }
    enum Confidence: Int, Sendable, Hashable, Comparable {
        case possible = 1, likely = 2, veryLikely = 3
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }
    enum Reason: String, Sendable, Hashable, CaseIterable {
        case noCameraData, chatFilename, chatDimensions, noLocation, jpegOnly, utilityLook
    }
    let confidence: Confidence
    let source: Source
    let reasons: [Reason]
}

nonisolated struct ChatSavedItem: Identifiable, Hashable, Sendable {
    var item: MediaItem
    let verdict: ChatSavedVerdict
    var id: String { item.id }
}

/// What an expired screenshot was, and when it stopped being useful.
nonisolated struct ExpiryVerdict: Sendable, Hashable {
    enum Kind: String, Sendable, Hashable, CaseIterable {
        case oneTimeCode, boardingPass, ticket, delivery, coupon, reservation, parking
    }
    let kind: Kind
    /// The moment the screenshot stopped mattering. Past `now` means expired.
    let expiresAt: Date
    /// A date found in the text that drove the verdict, if any (shown to the user).
    let mentionedDate: Date?
    /// 0…1. Only verdicts at or above the scanner's threshold are shown.
    let confidence: Float
}

nonisolated struct ExpiredScreenshot: Identifiable, Hashable, Sendable {
    var item: MediaItem
    let verdict: ExpiryVerdict
    var id: String { item.id }
}

