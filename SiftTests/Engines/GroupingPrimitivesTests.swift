import Foundation
import Testing
@testable import Sift

struct GroupingPrimitivesTests {
    @Test func multiIndexFindsEveryPairWithinThreeBits() {
        // Compare against brute force: the index must never miss a pair ≤ 3 bits apart.
        var rng = SplitMix64(seed: 42)
        var hashes: [UInt64] = []
        for _ in 0..<300 {
            let base = rng.next()
            hashes.append(base)
            // Near copies with 1–3 flipped bits.
            var copy = base
            for _ in 0..<Int.random(in: 1...3, using: &rng) { copy ^= 1 << UInt64(Int.random(in: 0..<64, using: &rng)) }
            hashes.append(copy)
        }
        var index = MultiIndexHash()
        for hash in hashes { index.insert(hash) }

        for (i, hash) in hashes.enumerated() {
            let expected = Set(hashes.indices.filter { ImageAnalysis.hamming(hashes[$0], hash) <= 3 })
            let found = Set(index.matches(for: hash, maxDistance: 3))
            #expect(found == expected, "Mismatch for hash \(i)")
        }
    }

    @Test func unionFindJoinsAndCounts() {
        var sets = UnionFind()
        for _ in 0..<5 { sets.add() }
        sets.union(0, 1)
        sets.union(3, 4)
        sets.union(1, 4)
        #expect(sets.find(0) == sets.find(3))
        #expect(sets.find(2) != sets.find(0))
        #expect(sets.size(of: 4) == 4)
    }

    @Test func favouriteAlwaysWins() {
        let ranked = BestShotRanker.rank([
            .init(id: "sharp", isFavorite: false, sharpness: 900, pixelCount: 12_000_000, date: nil),
            .init(id: "fav", isFavorite: true, sharpness: 10, pixelCount: 3_000_000, date: nil),
        ])
        #expect(ranked.first == "fav")
    }

    @Test func sharperShotWinsAtSameResolution() {
        let ranked = BestShotRanker.rank([
            .init(id: "soft", isFavorite: false, sharpness: 80, pixelCount: 12_000_000, date: nil),
            .init(id: "crisp", isFavorite: false, sharpness: 400, pixelCount: 12_000_000, date: nil),
        ])
        #expect(ranked == ["crisp", "soft"])
    }

    @Test func exactDuplicatesKeepTheHighestFidelityFile() {
        // The re-compressed copy scores "sharper" (JPEG artefacts), but it's the worse file.
        let ranked = BestShotRanker.rank([
            .init(id: "resaved", isFavorite: false, sharpness: 900, pixelCount: 12_000_000, date: nil, bytes: 90_000),
            .init(id: "original", isFavorite: false, sharpness: 400, pixelCount: 12_000_000, date: nil, bytes: 180_000),
        ], exactDuplicates: true)
        #expect(ranked == ["original", "resaved"])
    }

    @Test func neighbourFlagsMarkBothSidesOfAClosePair() {
        let d = { (s: Double) in Date(timeIntervalSinceReferenceDate: s) }
        let flags = SimilarityEngine.neighbourFlags([d(0), d(30), d(500), nil, d(2000)], window: 60)
        #expect(flags == [true, true, false, false, false])
    }
}
