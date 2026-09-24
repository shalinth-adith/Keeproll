#if DEBUG
import Foundation

// Fixture data for previews and the SIFT_DEMO run mode. Compiled out of release builds.
// Contact names here are invented; none are real people.

/// Builds similar-photo groups out of whatever image assets the library has, so
/// thumbnails are real while the grouping is fake.
nonisolated struct DemoSimilarity: SimilarityScanning {
    let photos: PhotoLibraryProviding

    func scan() -> AsyncStream<SimilarGroup> {
        AsyncStream { continuation in
            Task {
                let pool = await photos.fetchScreenshots()
                var index = 0
                var groupNumber = 0
                while index + 1 < pool.count {
                    let size = min([3, 2, 4][groupNumber % 3], pool.count - index)
                    let members = Array(pool[index..<index + size])
                    guard members.count > 1 else { break }
                    try? await Task.sleep(for: .milliseconds(350)) // stream in like a real scan
                    continuation.yield(SimilarGroup(
                        id: UUID(), kind: groupNumber % 3 == 1 ? .exactDuplicate : .similar,
                        members: members, bestID: members[0].id
                    ))
                    index += size
                    groupNumber += 1
                }
                continuation.finish()
            }
        }
    }
}

nonisolated struct DemoContacts: ContactsScanning {
    func findDuplicates() async -> [DuplicateContactGroup] {
        try? await Task.sleep(for: .milliseconds(600))
        return [
            DuplicateContactGroup(id: UUID(), contacts: [
                ContactSummary(id: "c1", givenName: "Priya", familyName: "Raman", organization: "", phones: ["+91 98400 12345"], emails: ["priya.r@example.test"], hasImage: true),
                ContactSummary(id: "c2", givenName: "Priya", familyName: "Raman", organization: "Meridian Labs", phones: ["+91 98400 12345", "+91 44 2811 0099"], emails: [], hasImage: false),
                ContactSummary(id: "c3", givenName: "Priya", familyName: "", organization: "", phones: ["98400 12345"], emails: [], hasImage: false),
            ], reasons: [.samePhone, .sameName]),
            DuplicateContactGroup(id: UUID(), contacts: [
                ContactSummary(id: "c4", givenName: "Arun", familyName: "Sekar", organization: "", phones: ["+91 90030 55511"], emails: ["arun@example.test"], hasImage: false),
                ContactSummary(id: "c5", givenName: "Arun", familyName: "S", organization: "", phones: [], emails: ["arun@example.test"], hasImage: false),
            ], reasons: [.sameEmail]),
            DuplicateContactGroup(id: UUID(), contacts: [
                ContactSummary(id: "c6", givenName: "Kavya", familyName: "Nair", organization: "", phones: ["+91 96000 77123"], emails: [], hasImage: false),
                ContactSummary(id: "c7", givenName: "Nair", familyName: "Kavya", organization: "", phones: ["+91 96000 77123"], emails: ["kavya.n@example.test"], hasImage: true),
            ], reasons: [.samePhone, .sameName]),
        ]
    }
}
#endif
