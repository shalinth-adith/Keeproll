import Foundation
import Testing
@testable import Sift

struct SimilarityGrouperTests {
    private var rng = SplitMix64(seed: 7)
    private mutating func hash() -> UInt64 { rng.next() }

    @Test mutating func burstWithinWindowBecomesOneGroup() {
        let grouper = SimilarityGrouper()
        grouper.add(features("a", at: 0, hash: hash(), print: unitPrint(0)))
        grouper.add(features("b", at: 2, hash: hash(), print: unitPrint(0.1)))
        grouper.add(features("c", at: 5, hash: hash(), print: unitPrint(0.15)))
        grouper.add(features("lone", at: 30, hash: hash(), print: unitPrint(2.5)))

        let groups = grouper.groups()
        #expect(groups.count == 1)
        #expect(Set(groups[0].memberIDs) == ["a", "b", "c"])
        #expect(groups[0].anchorID == "a")
        #expect(!groups[0].isExactDuplicate)
    }

    @Test mutating func sameLookingShotsOutsideTheWindowStayApart() {
        let grouper = SimilarityGrouper()
        grouper.add(features("morning", at: 0, hash: hash(), print: unitPrint(0)))
        grouper.add(features("evening", at: 36_000, hash: hash(), print: unitPrint(0)))
        #expect(grouper.groups().isEmpty)
    }

    @Test mutating func exactDuplicatesAreFoundAcrossTheLibrary() {
        let grouper = SimilarityGrouper()
        let shared = hash()
        grouper.add(features("original", at: 0, hash: shared))
        grouper.add(features("other", at: 50_000, hash: hash()))
        grouper.add(features("copy", at: 9_000_000, hash: shared ^ 0b101)) // 2 bits off
        let groups = grouper.groups()
        #expect(groups.count == 1)
        #expect(Set(groups[0].memberIDs) == ["original", "copy"])
        #expect(groups[0].isExactDuplicate)
    }

    @Test mutating func driftingChainIsCutByTheAnchorCheck() {
        // Each shot is close to the previous one, but the fourth has drifted too far
        // from the first. Without the anchor check all five would chain together.
        let grouper = SimilarityGrouper()
        for (i, angle) in [0, 0.3, 0.6, 0.9, 1.2].enumerated() {
            grouper.add(features("s\(i)", at: Double(i), hash: hash(), print: unitPrint(Float(angle))))
        }
        let groups = grouper.groups().map { Set($0.memberIDs) }
        #expect(groups == [["s0", "s1", "s2"], ["s3", "s4"]])
    }

    @Test mutating func fallsBackToHashesWithoutFeaturePrints() {
        let grouper = SimilarityGrouper()
        let base = hash()
        grouper.add(features("x", at: 0, hash: base))
        grouper.add(features("y", at: 3, hash: base ^ 0b1111_1100)) // 6 bits: similar, not duplicate
        let groups = grouper.groups()
        #expect(groups.count == 1)
        #expect(!groups[0].isExactDuplicate)
    }

    @Test mutating func groupsNeverExceedTheSizeCap() {
        var config = SimilarityConfig.standard
        config.maxGroupSize = 4
        config.maxNeighbours = 20
        let grouper = SimilarityGrouper(config: config)
        for i in 0..<10 { grouper.add(features("p\(i)", at: Double(i), hash: hash(), print: unitPrint(0))) }
        #expect(grouper.groups().allSatisfy { $0.memberIDs.count <= 4 })
    }
}

/// Scale check for "fast on a large library" (PRD §4): the grouping stage alone must
/// stay near-linear. 20k photos with realistic 768-float prints, in bursts.
struct SimilarityScaleTests {
    @Test func twentyThousandPhotosGroupQuickly() {
        var rng = SplitMix64(seed: 99)
        let grouper = SimilarityGrouper()
        var time: TimeInterval = 0
        let start = Date()
        for i in 0..<20_000 {
            // Bursts of 4 shots 1 s apart, then a gap; prints nearly equal within a burst.
            time += i % 4 == 0 ? 3_600 : 1
            var print = [Float](repeating: 0, count: 768)
            let base = (i / 4) % 768
            print[base] = 1
            print[(base + 1) % 768] = Float(i % 4) * 0.05
            grouper.add(features("p\(i)", at: time, hash: rng.next(), print: print))
        }
        let groups = grouper.groups()
        let elapsed = Date().timeIntervalSince(start)
        #expect(groups.count == 5_000)
        #expect(groups.allSatisfy { $0.memberIDs.count == 4 })
        #expect(elapsed < 20, "Grouping 20k photos took \(elapsed) s")
    }
}
