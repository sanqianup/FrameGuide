import XCTest
#if SWIFT_PACKAGE
@testable import CompositionCore
#else
@testable import FrameGuide
#endif

final class GuidedCompositionTests: XCTestCase {
    private let seed = Subject(x: 0.16, y: 0.22, width: 0.24, height: 0.40, confidence: 0.9)
    func testTapChoosesContainingSmallestSubjectRatherThanLargestPerson() {
        let large = Subject(x: 0.1, y: 0.1, width: 0.7, height: 0.8, confidence: 1)
        XCTAssertEqual(SubjectSelection.seed(x: 0.2, y: 0.3, candidates: [large, seed]), seed)
    }
    func testBackgroundTapCreatesBoundedRegionAndInvalidPointsAreRejected() throws {
        let region = try XCTUnwrap(SubjectSelection.seed(x: 1, y: 0, candidates: []))
        XCTAssertTrue(region.isValid)
        XCTAssertNil(SubjectSelection.seed(x: .nan, y: 0, candidates: []))
        XCTAssertNil(SubjectSelection.seed(x: -0.01, y: 0.2, candidates: []))
    }
    func testFixedTargetDoesNotChaseMovingSubject() throws {
        var guide = GuidedComposition(); guide.begin(seed)
        let initial = try XCTUnwrap(guide.target)
        var moved = seed; moved.x += 0.2
        let result = try XCTUnwrap(guide.update(moved, stable: true, now: 0))
        XCTAssertEqual(result.target, initial)
        XCTAssertEqual(result.direction, .left)
        XCTAssertFalse(result.aligned)
    }
    func testAlignmentRequiresContinuousHoldAndHasExitHysteresis() throws {
        var guide = GuidedComposition(); guide.begin(seed)
        var aligned = try XCTUnwrap(guide.target)
        XCTAssertFalse(try XCTUnwrap(guide.update(aligned, stable: true, now: 0)).aligned)
        XCTAssertTrue(try XCTUnwrap(guide.update(aligned, stable: true, now: 0.7)).aligned)
        aligned.x += 0.06
        XCTAssertTrue(try XCTUnwrap(guide.update(aligned, stable: true, now: 0.9)).aligned)
        aligned.x += 0.05
        XCTAssertFalse(try XCTUnwrap(guide.update(aligned, stable: true, now: 1.1)).aligned)
    }
    func testIntermittentAlignmentAndStaleDecisionsCannotClaimArrival() throws {
        var guide = GuidedComposition(); guide.begin(seed)
        let aligned = try XCTUnwrap(guide.target)
        _ = guide.update(aligned, stable: true, now: 0)
        var outside = aligned; outside.y += 0.12
        _ = guide.update(outside, stable: true, now: 0.3)
        XCTAssertFalse(try XCTUnwrap(guide.update(aligned, stable: true, now: 0.8)).aligned)
        XCTAssertFalse(try XCTUnwrap(guide.update(aligned, stable: true, now: 4)).aligned)
    }
    func testMotionAndLossRemoveTargetRatherThanPreserveStaleDirection() {
        var guide = GuidedComposition(); guide.begin(seed)
        XCTAssertNil(guide.update(seed, stable: false, now: 0)); XCTAssertNil(guide.target)
        guide.begin(seed)
        XCTAssertNil(guide.update(nil, stable: true, now: 1)); XCTAssertNil(guide.target)
        guide.begin(seed)
        var low = seed; low.confidence = 0.6
        XCTAssertNil(guide.update(low, stable: true, now: 2)); XCTAssertNil(guide.target)
    }
    func testZoomSuggestionRequiresPositionMatchAndIsOnlyRelativeCrop() throws {
        var guide = GuidedComposition()
        let tiny = Subject(x: 0.1, y: 0.1, width: 0.12, height: 0.18, confidence: 1)
        guide.begin(tiny)
        XCTAssertNil(try XCTUnwrap(guide.update(tiny, stable: true, now: 0)).relativeZoom)
        let target = try XCTUnwrap(guide.target)
        let centered = Subject(x: target.x + target.width / 2 - tiny.width / 2,
                               y: target.y + target.height / 2 - tiny.height / 2,
                               width: tiny.width, height: tiny.height, confidence: 1)
        let zoom = try XCTUnwrap(guide.update(centered, stable: true, now: 0.5)?.relativeZoom)
        XCTAssertGreaterThan(zoom, 1.22); XCTAssertLessThanOrEqual(zoom, 1.8)
    }
    func testTrackingFreshnessRejectsLateOrReorderedHandoffs() {
        var lease = TrackingFreshness()
        XCTAssertTrue(lease.expired(now: 0))
        XCTAssertTrue(lease.accept(captured: 5, now: 5.2))
        XCTAssertFalse(lease.accept(captured: 4.9, now: 5.3))
        XCTAssertFalse(lease.accept(captured: 5.1, now: 7))
        XCTAssertFalse(lease.expired(now: 6))
        XCTAssertTrue(lease.expired(now: 6.3))
        XCTAssertTrue(lease.expired(now: 4)); XCTAssertTrue(lease.expired(now: .nan))
    }
    func testThermalTrackingAndDecisionBudgetsRemainSeparate() {
        let normal = AnalysisPolicy.make(heat: .nominal, lowPower: false, memoryPressure: false)
        XCTAssertEqual(normal.trackingInterval, 0.125); XCTAssertEqual(normal.interval, 0.4)
        let hot = AnalysisPolicy.make(heat: .serious, lowPower: false, memoryPressure: false)
        XCTAssertEqual(hot.trackingInterval, 0.5); XCTAssertEqual(hot.interval, 1.5)
        XCTAssertEqual(AnalysisPolicy.make(heat: .critical, lowPower: false, memoryPressure: false).trackingInterval, .infinity)
    }
    func testDigitalZoomClampsDeviceRangeAndCanReturnToOne() {
        XCTAssertEqual(DigitalZoom.requested(current: 2, factor: 1.8, minimum: 1, maximum: 8), 3)
        XCTAssertEqual(DigitalZoom.requested(current: 3, factor: 1.0 / 3, minimum: 1, maximum: 8), 1)
        XCTAssertEqual(DigitalZoom.requested(current: 1, factor: 1.8, minimum: 1, maximum: 1.4), 1.4)
        XCTAssertNil(DigitalZoom.requested(current: 1, factor: .nan, minimum: 1, maximum: 8))
        XCTAssertNil(DigitalZoom.requested(current: 1, factor: 1.2, minimum: 2, maximum: 1))
    }
    func testAllLocalLooksAreSafeAndRecommendationsDoNotModifyPixels() {
        XCTAssertEqual(LocalLook.allCases.count, 3)
        for look in LocalLook.allCases { XCTAssertTrue(look.recipe.isSafe) }
        XCTAssertEqual(LocalLook.suggest(person: true, luminance: 0.5), .softPortrait)
        XCTAssertEqual(LocalLook.suggest(person: false, luminance: 0.1), .natural)
        XCTAssertEqual(LocalLook.suggest(person: false, luminance: 0.6), .clearScene)
    }
}
