import OSLog

/// Loggers per area. Privacy rule: never log contact names, numbers, emails or file
/// names. Log counts, and mark any identifier `privacy: .private`.
nonisolated enum Log {
    private static let subsystem = "me.adithyan.shalinth.Sift"

    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let contacts = Logger(subsystem: subsystem, category: "contacts")
    static let cleanup = Logger(subsystem: subsystem, category: "cleanup")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let perf = Logger(subsystem: subsystem, category: "perf")
}

/// Signpost intervals used to check the PRD §4 performance targets in Instruments.
nonisolated enum Signposts {
    static let scan = OSSignposter(subsystem: "me.adithyan.shalinth.Sift", category: "scan")
    static let cleanup = OSSignposter(subsystem: "me.adithyan.shalinth.Sift", category: "cleanup")
}
