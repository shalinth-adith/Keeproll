import Foundation

/// Finds near-duplicate 64-bit hashes without comparing every pair.
///
/// The hash is split into four 16-bit bands, each with its own lookup table. If two
/// hashes differ in at most 3 bits, at least one of the four bands must be identical
/// (pigeonhole), so looking up each band finds every match. That makes a whole-library
/// duplicate search roughly O(n) instead of O(n²).
nonisolated struct MultiIndexHash {
    private var bands: [[UInt16: [Int]]] = Array(repeating: [:], count: 4)
    private(set) var hashes: [UInt64] = []

    /// Adds a hash and returns its index.
    @discardableResult
    mutating func insert(_ hash: UInt64) -> Int {
        let index = hashes.count
        hashes.append(hash)
        for band in 0..<4 {
            bands[band][Self.band(hash, band), default: []].append(index)
        }
        return index
    }

    /// Indices of stored hashes within `maxDistance` bits of `hash`. Exact (no misses)
    /// for `maxDistance` ≤ 3; above that it can miss pairs.
    func matches(for hash: UInt64, maxDistance: Int) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for band in 0..<4 {
            for index in bands[band][Self.band(hash, band)] ?? [] where seen.insert(index).inserted {
                if ImageAnalysis.hamming(hashes[index], hash) <= maxDistance { result.append(index) }
            }
        }
        return result
    }

    private static func band(_ hash: UInt64, _ band: Int) -> UInt16 {
        UInt16(truncatingIfNeeded: hash >> (UInt64(band) * 16))
    }
}

/// Disjoint-set forest with path compression and union by size.
nonisolated struct UnionFind {
    private var parent: [Int] = []
    private var sizes: [Int] = []

    var count: Int { parent.count }

    @discardableResult
    mutating func add() -> Int {
        parent.append(parent.count)
        sizes.append(1)
        return parent.count - 1
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func size(of x: Int) -> Int { sizes[find(x)] }

    /// Joins the two sets; returns the new root.
    @discardableResult
    mutating func union(_ a: Int, _ b: Int) -> Int {
        var ra = find(a), rb = find(b)
        guard ra != rb else { return ra }
        if sizes[ra] < sizes[rb] { swap(&ra, &rb) }
        parent[rb] = ra
        sizes[ra] += sizes[rb]
        return ra
    }
}

/// Picks the photo to keep in a group (FR-SIM-3).
///
/// - Favourites always win.
/// - Exact duplicates show the same picture, so keep the highest-fidelity file (the
///   biggest one), then the earliest. Sharpness would mislead here: re-compression
///   artefacts read as extra "edges".
/// - Similar shots: a blend of sharpness and resolution, then the earliest.
nonisolated enum BestShotRanker {
    nonisolated struct Candidate: Sendable {
        let id: String
        let isFavorite: Bool
        let sharpness: Float
        let pixelCount: Int
        let date: Date?
        var bytes: Int64 = 0
    }

    /// Candidate ids, best first.
    static func rank(_ candidates: [Candidate], exactDuplicates: Bool = false) -> [String] {
        if exactDuplicates {
            return candidates.sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                if a.pixelCount != b.pixelCount { return a.pixelCount > b.pixelCount }
                if a.bytes != b.bytes { return a.bytes > b.bytes }
                return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
            }.map(\.id)
        }
        let maxSharpness = max(candidates.map(\.sharpness).max() ?? 1, 0.0001)
        let maxPixels = Double(max(candidates.map(\.pixelCount).max() ?? 1, 1))
        func score(_ c: Candidate) -> Double {
            0.7 * Double(c.sharpness / maxSharpness) + 0.3 * Double(c.pixelCount) / maxPixels
        }
        return candidates.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            let sa = score(a), sb = score(b)
            if abs(sa - sb) > 0.0001 { return sa > sb }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }.map(\.id)
    }
}
