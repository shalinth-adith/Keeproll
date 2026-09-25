import Contacts
import EventKit
import Photos
import PhotosUI
import UIKit

nonisolated protocol PermissionServicing: Sendable {
    func photosState() -> PermissionState
    func requestPhotos() async -> PermissionState
    func contactsState() -> PermissionState
    func requestContacts() async -> PermissionState
    func calendarState() -> PermissionState
    func requestCalendar() async -> PermissionState
}

nonisolated final class PermissionService: PermissionServicing {
    func photosState() -> PermissionState {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestPhotos() async -> PermissionState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        Log.photos.debug("Photos authorization answered: \(String(describing: status.rawValue), privacy: .public)")
        return Self.map(status)
    }

    func contactsState() -> PermissionState {
        Self.map(CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestContacts() async -> PermissionState {
        do {
            _ = try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            Log.contacts.error("Contacts access request failed: \(error.localizedDescription, privacy: .public)")
        }
        return contactsState()
    }

    func calendarState() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .fullAccess: .authorized
        // Write-only can't read events, so for cleanup it's the same as denied.
        case .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    func requestCalendar() async -> PermissionState {
        do {
            _ = try await EKEventStore().requestFullAccessToEvents()
        } catch {
            Log.scan.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
        return calendarState()
    }

    private static func map(_ status: PHAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        case .limited: .limited
        @unknown default: .denied
        }
    }

    private static func map(_ status: CNAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        default:
            // `.limited` exists on iOS 18+ only (FR-PERM-6).
            if #available(iOS 18.0, *), status == .limited { return .limited }
            return .denied
        }
    }
}

/// Opening Settings and the limited-library picker need UIKit.
@MainActor
enum SystemActions {
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens the Photos app (where Recently Deleted lives).
    static func openPhotos() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }

    /// Shows the system picker to change which photos Keeproll can see (FR-PERM-5).
    static func presentLimitedLibraryPicker() async {
        guard let root = topViewController() else { return }
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root) { ids in
                continuation.resume(returning: ids)
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
