import Foundation

/// When to ask for an App Store rating. Pure; tested in `GrowthTests`.
///
/// Once per install, only after a cleanup that freed at least `minimumBytes`, and
/// never in the first session: the person has to have come back and had a good
/// result. Apple allows three asks a year; one is enough.
nonisolated enum ReviewPrompter {
    static let minimumBytes: Int64 = 500_000_000
    static let minimumSession = 2

    static func shouldAsk(bytesFreed: Int64, sessionCount: Int, alreadyAsked: Bool, failures: Int) -> Bool {
        !alreadyAsked && failures == 0 && bytesFreed >= minimumBytes && sessionCount >= minimumSession
    }
}
