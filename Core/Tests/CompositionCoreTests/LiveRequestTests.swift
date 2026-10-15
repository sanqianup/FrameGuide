import XCTest
#if SWIFT_PACKAGE
@testable import CompositionCore
#else
@testable import FrameGuide
#endif

final class LiveRequestTests: XCTestCase {
    private func ready() -> LiveRequestGate {
        var gate = LiveRequestGate(); gate.invalidate(lens: "wide", rotation: 90); return gate
    }
    func testCannotSampleWithoutEligibilityAndRejectsRapidClicks() throws {
        var gate = ready()
        XCTAssertNil(gate.begin(now: 0, eligible: false))
        _ = try XCTUnwrap(gate.begin(now: 0, eligible: true))
        XCTAssertNil(gate.begin(now: 0.1, eligible: true))
    }
    func testCannotSubmitBeforeSnapshotAndConfirmation() throws {
        var gate = ready(); let t = try XCTUnwrap(gate.begin(now: 0, eligible: true))
        XCTAssertFalse(gate.confirm(t, now: 0.1, eligible: true))
        XCTAssertTrue(gate.sampled(t, now: 0.2))
        XCTAssertFalse(gate.accepts(t, now: 0.3))
        XCTAssertTrue(gate.confirm(t, now: 0.4, eligible: true))
        XCTAssertTrue(gate.accepts(t, now: 0.5))
        XCTAssertFalse(gate.confirm(t, now: 0.5, eligible: true))
    }
    func testOldResponseRejectedAfterMovementLensRotationAndBackground() throws {
        for (lens, angle) in [("wide", 90), ("front", 90), ("wide", 0), ("", 90)] {
            var gate = ready(); let t = try XCTUnwrap(gate.begin(now: 0, eligible: true))
            XCTAssertTrue(gate.sampled(t, now: 0.1)); XCTAssertTrue(gate.confirm(t, now: 0.2, eligible: true))
            gate.invalidate(lens: lens, rotation: angle)
            XCTAssertFalse(gate.accepts(t, now: 0.5))
        }
    }
    func testFrozenSnapshotExpiresWhileConfirmationIsOpen() throws {
        var gate = ready(); let t = try XCTUnwrap(gate.begin(now: 0, eligible: true))
        XCTAssertTrue(gate.sampled(t, now: 0.1))
        XCTAssertFalse(gate.confirm(t, now: 15.01, eligible: true))
    }
    func testCooldownSurvivesSceneChangesAndRejectsOldCompletions() throws {
        var gate = ready(); let old = try XCTUnwrap(gate.begin(now: 0, eligible: true))
        XCTAssertTrue(gate.sampled(old, now: 0.1)); XCTAssertTrue(gate.confirm(old, now: 1, eligible: true))
        gate.invalidate(lens: "tele", rotation: 90)
        XCTAssertNil(gate.begin(now: 8.9, eligible: true))
        let new = try XCTUnwrap(gate.begin(now: 9, eligible: true))
        gate.finish(old)
        XCTAssertEqual(gate.ticket, new)
    }
    func testSamplingTimeoutAndReversedClockFailClosed() throws {
        var gate = ready(); let t = try XCTUnwrap(gate.begin(now: 1, eligible: true))
        XCTAssertFalse(gate.sampled(t, now: 0))
        XCTAssertFalse(gate.sampled(t, now: 4.01))
        XCTAssertFalse(gate.sampled(t, now: .nan))
    }
    func testResponseAgeLimitAndSamplingCooldownAcrossCancel() throws {
        var gate = ready(); let t = try XCTUnwrap(gate.begin(now: 0, eligible: true))
        XCTAssertTrue(gate.sampled(t, now: 0.1)); XCTAssertTrue(gate.confirm(t, now: 0.2, eligible: true))
        XCTAssertFalse(gate.accepts(t, now: 30.01))
        gate.invalidate(lens: "wide", rotation: 90)
        XCTAssertNil(gate.begin(now: 0.3, eligible: true))
    }
    func testSceneFingerprintInvalidatesAccumulatedChangeAndRejectsBadInput() {
        var f = SceneFingerprint()
        XCTAssertFalse(f.changed(Array(repeating: 0.3, count: 64)))
        XCTAssertFalse(f.changed(Array(repeating: 0.35, count: 64)))
        XCTAssertTrue(f.changed(Array(repeating: 0.5, count: 64)))
        XCTAssertFalse(f.changed(Array(repeating: 0.5, count: 64)))
        XCTAssertFalse(f.changed([.nan]))
    }
}
