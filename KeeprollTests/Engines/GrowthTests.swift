import Foundation
import Testing
@testable import Keeproll

struct ReviewPrompterTests {
    @Test func asksOnceAfterAGoodSecondSessionCleanup() {
        #expect(ReviewPrompter.shouldAsk(bytesFreed: 600_000_000, sessionCount: 2, alreadyAsked: false, failures: 0))
    }
    @Test func neverInTheFirstSession() {
        #expect(!ReviewPrompter.shouldAsk(bytesFreed: 5_000_000_000, sessionCount: 1, alreadyAsked: false, failures: 0))
    }
    @Test func notForSmallCleanups() {
        #expect(!ReviewPrompter.shouldAsk(bytesFreed: 120_000_000, sessionCount: 5, alreadyAsked: false, failures: 0))
    }
    @Test func notTwiceAndNotAfterFailures() {
        #expect(!ReviewPrompter.shouldAsk(bytesFreed: 900_000_000, sessionCount: 3, alreadyAsked: true, failures: 0))
        #expect(!ReviewPrompter.shouldAsk(bytesFreed: 900_000_000, sessionCount: 3, alreadyAsked: false, failures: 1))
    }
}

struct WhatsNewTests {
    @Test func freshInstallSeesNothing() {
        #expect(!WhatsNew.shouldShow(lastSeen: nil, current: "4"))
    }
    @Test func sameBuildSeesNothing() {
        #expect(!WhatsNew.shouldShow(lastSeen: "4", current: "4"))
    }
    @Test func updatedBuildWithNotesShowsOnce() {
        #expect(WhatsNew.shouldShow(lastSeen: "3", current: "4"))
        #expect(WhatsNew.items(for: "4").count == 4)
    }
    @Test func buildWithoutNotesIsSilent() {
        #expect(!WhatsNew.shouldShow(lastSeen: "4", current: "99"))
    }
}
