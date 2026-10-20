import Foundation

/// One entry on the What's New sheet.
nonisolated struct WhatsNewItem: Identifiable, Sendable, Equatable {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    var id: String { symbol }
}

/// What changed, keyed by build so TestFlight testers see it too. Pure; tested in `GrowthTests`.
nonisolated enum WhatsNew {
    static var currentBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    /// Newest first. Add an entry per release; the sheet shows the one for the running build.
    static let releases: [(build: String, items: [WhatsNewItem])] = [
        ("5", [
            WhatsNewItem(symbol: "hand.raised.fingers.spread", title: "Accidental Shots", detail: "Pocket shots, black frames and a finger over the lens, found for you."),
            WhatsNewItem(symbol: "scissors", title: "Smart Trim", detail: "Cuts the dark, empty stretches out of videos and keeps the rest at full quality."),
            WhatsNewItem(symbol: "clock.arrow.circlepath", title: "Backups in Settings", detail: "Contact and calendar backups are now listed in Settings, to share or delete."),
        ]),
        ("4", [
            WhatsNewItem(symbol: "bubble.left.and.bubble.right", title: "Saved from Chats", detail: "Photos that arrived through WhatsApp and Telegram, told apart from the ones you shot."),
            WhatsNewItem(symbol: "clock.badge.xmark", title: "Expired Screenshots", detail: "Codes, passes and tickets that are past their date, read on your iPhone."),
            WhatsNewItem(symbol: "livephoto", title: "Live Photos to stills", detail: "Keep the still, drop the clip. Same date and place."),
            WhatsNewItem(symbol: "chart.line.uptrend.xyaxis", title: "Storage forecast", detail: "Home tells you where your free space is heading."),
        ]),
    ]

    /// Show when the build changed since the last sheet, but not on a fresh install
    /// (`lastSeen == nil`) and not when nothing is written for this build.
    static func shouldShow(lastSeen: String?, current: String = currentBuild) -> Bool {
        guard let lastSeen, lastSeen != current else { return false }
        return releases.contains { $0.build == current }
    }

    static func items(for build: String = currentBuild) -> [WhatsNewItem] { releases.first { $0.build == build }?.items ?? [] }
}
