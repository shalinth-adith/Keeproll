import LocalAuthentication

nonisolated enum VaultUnlockResult: Sendable, Equatable {
    case unlocked
    case cancelled
    /// No passcode on the device, so nothing can protect the vault.
    case unavailable(String)
}

nonisolated protocol VaultAuthenticating: Sendable {
    func unlock() async -> VaultUnlockResult
}

/// Face ID / Touch ID with the device passcode as fallback: the "PIN or Face ID" in the
/// brief, without Sift ever storing a PIN of its own.
nonisolated struct DeviceOwnerAuthenticator: VaultAuthenticating {
    func unlock() async -> VaultUnlockResult {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(String(localized: "Set a passcode in Settings to use the vault. Without one, nothing can protect it."))
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: String(localized: "Unlock your private vault"))
            return ok ? .unlocked : .cancelled
        } catch {
            return .cancelled
        }
    }
}
