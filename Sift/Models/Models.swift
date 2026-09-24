import Foundation
import SwiftUI

// Value types that cross actor boundaries. They carry identifiers, never PhotoKit or
// Contacts objects (those are not Sendable).

nonisolated enum CleanupCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
    case similar, screenshots, videos, contacts
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .similar: "Similar Photos"
        case .screenshots: "Screenshots"
        case .videos: "Large Videos"
        case .contacts: "Duplicate Contacts"
        }
    }

    var symbol: String {
        switch self {
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .videos: "video"
        case .contacts: "person.2"
        }
    }

    @MainActor var color: Color {
        switch self {
        case .similar: Color.sift.catSimilar
        case .screenshots: Color.sift.catScreenshots
        case .videos: Color.sift.catVideos
        case .contacts: Color.sift.catContacts
        }
    }
}

nonisolated struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case photo, screenshot, video }

    /// `PHAsset.localIdentifier`.
    let id: String
    let kind: Kind
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval?
    let isFavorite: Bool
    /// Filled in by `AssetSizeService`; nil until known.
    var byteSize: Int64?
    /// True when the size is a pixel-count estimate rather than the real file size.
    var sizeIsEstimated: Bool = false
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

    var key: String {
        switch self {
        case .asset(let id, _, _): "asset:\(id)"
        }
    }

    var category: CleanupCategory {
        switch self {
        case .asset(_, let category, _): category
        }
    }

    var bytes: Int64 {
        switch self {
        case .asset(_, _, let bytes): bytes
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
        case .permissionDenied(.photos): String(localized: "Sift doesn't have access to your photos.")
        case .permissionDenied(.contacts): String(localized: "Sift doesn't have access to your contacts.")
        case .photoLibrary: String(localized: "Something went wrong reading your photo library. Please try again.")
        case .storageUnavailable: String(localized: "Couldn't read this iPhone's storage.")
        }
    }
}
