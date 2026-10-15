import XCTest
#if SWIFT_PACKAGE
@testable import CompositionCore
#else
@testable import FrameGuide
#endif

/// Exercises the same publication gate used by FrameAnalyzer and its main-queue handoff.
final class AnalysisEpochTests: XCTestCase {
    private func running() -> AnalysisEpoch {
        var epoch = AnalysisEpoch()
        epoch.configure(enabled: true); epoch.setStable(true)
        return epoch
    }
    func testMovementRejectsInferenceAlreadyInFlight() throws {
        var epoch = running()
        let inFlight = try XCTUnwrap(epoch.ticket)
        epoch.setStable(false)
        XCTAssertNil(epoch.ticket)
        XCTAssertFalse(epoch.accepts(inFlight))
    }
    func testRestabilizationCannotReviveOldInference() throws {
        var epoch = running()
        let beforeMovement = try XCTUnwrap(epoch.ticket)
        epoch.setStable(false); epoch.setStable(true)
        XCTAssertFalse(epoch.accepts(beforeMovement))
        let fresh = try XCTUnwrap(epoch.ticket)
        XCTAssertTrue(epoch.accepts(fresh))
        XCTAssertNotEqual(fresh, beforeMovement)
    }
    func testAlreadyCompletedResultIsRejectedAtMainQueueHandoff() throws {
        var epoch = running()
        let queuedResult = try XCTUnwrap(epoch.ticket)
        XCTAssertTrue(epoch.accepts(queuedResult)) // Vision completed before movement.
        epoch.setStable(false); epoch.setStable(true)
        var displayed: Int?
        if epoch.accepts(queuedResult) { displayed = queuedResult }
        XCTAssertNil(displayed) // Main queue must recheck, even if stable again.
    }
    func testSessionReconfigurationInvalidatesCurrentResult() throws {
        var epoch = running()
        let old = try XCTUnwrap(epoch.ticket)
        epoch.configure(enabled: false)
        XCTAssertFalse(epoch.accepts(old)); XCTAssertNil(epoch.ticket)
        epoch.configure(enabled: true)
        XCTAssertFalse(epoch.accepts(old))
        XCTAssertTrue(epoch.accepts(try XCTUnwrap(epoch.ticket)))
    }
    func testRepeatedUnstableStateDoesNotAdmitOrAdvanceWork() {
        var epoch = AnalysisEpoch(); epoch.configure(enabled: true)
        let revision = epoch.revision
        XCTAssertFalse(epoch.setStable(false))
        XCTAssertEqual(epoch.revision, revision)
        XCTAssertNil(epoch.ticket)
    }
}
