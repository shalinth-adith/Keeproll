import Foundation

/// Compact per-photo features. Everything the grouper needs; no images.
nonisolated struct AssetFeatures: Sendable {
    let id: String
    let date: Date?
    let dHash: UInt64
    let sharpness: Float
    var print: [Float]?
    let isFavorite: Bool
    let pixelCount: Int
}

/// Builds similar-photo groups incrementally from features fed in date order
/// (ARCHITECTURE §6.1). Two candidate sources, neither O(n²):
///
/// 1. **Duplicates anywhere:** each photo's dHash is looked up in a multi-index table.
/// 2. **Similar shots:** each photo is compared with at most `maxNeighbours` earlier
///    photos taken within `timeWindow` seconds.
///
/// Accepted pairs are joined with union-find, guarded by an anchor check so chains
/// don't drift into one giant group.
nonisolated final class SimilarityGrouper {
    struct Group: Equatable {
        let anchorID: String
        let memberIDs: [String]
        let isExactDuplicate: Bool
    }

    let config: SimilarityConfig
    private(set) var features: [AssetFeatures] = []
    private var sets = UnionFind()
    private var hashIndex = MultiIndexHash()
    /// Indices of dated photos still inside the time window, oldest first.
    private var window: [Int] = []
    /// Root → index of the group's earliest member (its anchor).
    private var anchor: [Int: Int] = [:]
    /// Roots whose group contains at least one "similar" (not duplicate) edge.
    private var hasSimilarEdge: Set<Int> = []
    /// Root → members, kept only for groups of two or more, so `groups()` costs
    /// O(groups) rather than O(library) and can run after every batch.
    private var memberLists: [Int: [Int]] = [:]
    /// Roots whose group changed since the last `drainChanges()`, and anchors of groups
    /// that were merged into another (so their old identity must be retired).
    private var dirtyRoots: Set<Int> = []
    private var vanishedAnchors: [String] = []

    /// Called for every time-window comparison with the two asset ids, the feature
    /// distance, the dHash distance and seconds apart. DEBUG calibration only.
    var onCompare: ((String, String, Float?, Int, TimeInterval) -> Void)?

    init(config: SimilarityConfig = .standard) {
        self.config = config
    }

    var count: Int { features.count }

    /// Adds one photo. Photos must arrive sorted by date (undated ones anywhere).
    func add(_ feature: AssetFeatures) {
        let index = features.count
        features.append(feature)
        sets.add()
        hashIndex.insert(feature.dHash)
        anchor[index] = index

        // 1. Exact / re-saved duplicates, anywhere in the library.
        for other in hashIndex.matches(for: feature.dHash, maxDistance: config.duplicateHashDistance) where other != index {
            join(index, other, similarEdge: false)
        }

        // 2. Near-identical shots inside the time window.
        guard let date = feature.date else { return }
        while let first = window.first, let firstDate = features[first].date,
              date.timeIntervalSince(firstDate) > config.timeWindow {
            window.removeFirst()
            releasePrintIfUnneeded(first)
        }
        for other in window.suffix(config.maxNeighbours).reversed() {
            if let onCompare {
                let distance = features[index].print.flatMap { a in features[other].print.map { FeaturePrinter.distance(a, $0) } }
                let seconds = features[other].date.map { date.timeIntervalSince($0) } ?? 0
                onCompare(features[index].id, features[other].id, distance,
                          ImageAnalysis.hamming(features[index].dHash, features[other].dHash), seconds)
            }
            if areSimilar(index, other, slack: 1) { join(index, other, similarEdge: true) }
        }
        window.append(index)
    }

    /// Current groups of two or more, in the order their anchors were added.
    func groups() -> [Group] {
        memberLists.compactMap { root, indices -> (Int, Group)? in
            guard indices.count > 1 else { return nil }
            let anchorIndex = anchor[root] ?? indices.min()!
            return (anchorIndex, Group(
                anchorID: features[anchorIndex].id,
                memberIDs: indices.map { features[$0].id },
                isExactDuplicate: !hasSimilarEdge.contains(root)
            ))
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    /// Groups that changed since the last call, plus anchors of groups that merged away.
    /// Lets the engine stream updates in O(changes) instead of re-diffing every group.
    func drainChanges() -> (changed: [Group], vanishedAnchorIDs: [String]) {
        var changed: [Group] = []
        for root in dirtyRoots where sets.find(root) == root {
            guard let indices = memberLists[root], indices.count > 1 else { continue }
            let anchorIndex = anchor[root] ?? indices.min()!
            changed.append(Group(anchorID: features[anchorIndex].id, memberIDs: indices.map { features[$0].id },
                                 isExactDuplicate: !hasSimilarEdge.contains(root)))
        }
        let vanished = vanishedAnchors
        dirtyRoots.removeAll()
        vanishedAnchors.removeAll()
        return (changed, vanished)
    }

    // MARK: - Private

    private func areSimilar(_ a: Int, _ b: Int, slack: Float) -> Bool {
        if let pa = features[a].print, let pb = features[b].print {
            return FeaturePrinter.distance(pa, pb) <= config.featureThreshold * slack
        }
        let limit = Int(Float(config.fallbackHashDistance) * slack)
        return ImageAnalysis.hamming(features[a].dHash, features[b].dHash) <= limit
    }

    private func join(_ a: Int, _ b: Int, similarEdge: Bool) {
        let ra = sets.find(a), rb = sets.find(b)
        guard ra != rb else {
            if similarEdge { hasSimilarEdge.insert(ra) }
            return
        }
        guard sets.size(of: ra) + sets.size(of: rb) <= config.maxGroupSize else { return }

        // Anchor check: the two groups' first photos must also look alike.
        let anchorA = anchor[ra] ?? ra, anchorB = anchor[rb] ?? rb
        if anchorA != a || anchorB != b {
            let anchorsMatch = similarEdge
                ? areSimilar(anchorA, anchorB, slack: config.anchorSlack)
                : ImageAnalysis.hamming(features[anchorA].dHash, features[anchorB].dHash) <= config.duplicateHashDistance + 2
            guard anchorsMatch else { return }
        }

        let sizeA = sets.size(of: ra), sizeB = sets.size(of: rb)
        let root = sets.union(ra, rb)
        let merged = (memberLists.removeValue(forKey: ra) ?? [ra]) + (memberLists.removeValue(forKey: rb) ?? [rb])
        memberLists[root] = merged
        let newAnchor = min(anchorA, anchorB)
        // A real group (2+) whose anchor lost the merge no longer exists under that anchor.
        if anchorA != newAnchor && sizeA > 1 { vanishedAnchors.append(features[anchorA].id) }
        if anchorB != newAnchor && sizeB > 1 { vanishedAnchors.append(features[anchorB].id) }
        anchor[root] = newAnchor
        dirtyRoots.remove(root == ra ? rb : ra)
        dirtyRoots.insert(root)
        if similarEdge || hasSimilarEdge.contains(ra) || hasSimilarEdge.contains(rb) { hasSimilarEdge.insert(root) }
        hasSimilarEdge.remove(root == ra ? rb : ra)
    }

    /// Once a photo leaves the time window its print is only needed if it anchors a
    /// group (for the anchor check). Dropping the rest keeps memory flat.
    private func releasePrintIfUnneeded(_ index: Int) {
        let root = sets.find(index)
        if anchor[root] == index && sets.size(of: index) > 1 { return }
        features[index].print = nil
    }
}
