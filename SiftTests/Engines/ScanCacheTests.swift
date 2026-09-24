import Foundation
import Testing
@testable import Sift

struct ScanCacheTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("scan-cache-\(UUID().uuidString).bin")
    }

    @Test func roundTripsThroughDisk() async {
        let url = tempURL()
        let modified = Date(timeIntervalSinceReferenceDate: 1_000)
        let record = ScanCache.FeatureRecord(modified: modified.timeIntervalSinceReferenceDate, dHash: 0xDEAD_BEEF,
                                             sharpness: 123.5, print: [0.1, 0.2, 0.3])
        let first = ScanCache(url: url)
        await first.store(record, for: "asset/1")
        await first.store(.init(modified: 5, dHash: 7, sharpness: 1, print: nil), for: "asset/2")
        await first.storeSize(4_200_000, for: "asset/1", modified: modified)
        await first.save()

        let second = ScanCache(url: url)
        #expect(await second.feature(for: "asset/1", modified: modified) == record)
        #expect(await second.feature(for: "asset/2", modified: Date(timeIntervalSinceReferenceDate: 5))?.print == nil)
        #expect(await second.size(for: "asset/1", modified: modified) == 4_200_000)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func editedAssetsMissTheCache() async {
        let cache = ScanCache(url: tempURL())
        await cache.store(.init(modified: 100, dHash: 1, sharpness: 1, print: nil), for: "a")
        #expect(await cache.feature(for: "a", modified: Date(timeIntervalSinceReferenceDate: 100)) != nil)
        #expect(await cache.feature(for: "a", modified: Date(timeIntervalSinceReferenceDate: 101)) == nil)
    }

    @Test func corruptFileStartsFresh() async throws {
        let url = tempURL()
        try Data("not a cache".utf8).write(to: url)
        let cache = ScanCache(url: url)
        #expect(await cache.featureCount == 0)
        try? FileManager.default.removeItem(at: url)
    }
}
