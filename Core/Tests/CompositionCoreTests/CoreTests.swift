import XCTest
#if SWIFT_PACKAGE
@testable import CompositionCore
#else
@testable import FrameGuide
#endif

final class CoreTests: XCTestCase {
    private func subject(_ x: Double = 0.5, _ y: Double = 0.32) -> Subject {
        Subject(x: x, y: y, width: 0.2, height: 0.2, confidence: 0.95)
    }
    func testDebounceAndPanDirection() {
        var guide = CompositionGuide()
        XCTAssertEqual(guide.update(subject: subject(0.68), stable: true, now: 0), .searching)
        XCTAssertEqual(guide.update(subject: subject(0.68), stable: true, now: 0.5), .panRight)
    }
    func testMotionClearsStaleAdvice() {
        var guide = CompositionGuide()
        _ = guide.update(subject: subject(), stable: true, now: 0)
        _ = guide.update(subject: subject(), stable: true, now: 0.5)
        XCTAssertEqual(guide.update(subject: subject(), stable: false, now: 0.6), .steady)
    }
    func testMissingSubjectExpires() {
        var guide = CompositionGuide()
        _ = guide.update(subject: subject(), stable: true, now: 0)
        _ = guide.update(subject: subject(), stable: true, now: 0.5)
        XCTAssertEqual(guide.update(subject: nil, stable: true, now: 1.5), .searching)
    }
    func testInvalidConfidenceAndCoordinates() {
        var guide = CompositionGuide()
        let bad = Subject(x: .nan, y: 0, width: 0.3, height: 0.4, confidence: 1)
        XCTAssertFalse(bad.isValid)
        XCTAssertFalse(Subject(x: 0.9, y: 0, width: 0.2, height: 0.4, confidence: 1).isValid)
        XCTAssertFalse(Subject(x: 0.2, y: 0, width: 0.2, height: 0.4, confidence: 0.1).isValid)
        XCTAssertEqual(guide.update(subject: bad, stable: true, now: 100), .searching)
    }
    func testAlignedDeadBand() {
        var guide = CompositionGuide()
        let aligned = subject(2.0 / 3 - 0.1)
        _ = guide.update(subject: aligned, stable: true, now: 0)
        XCTAssertEqual(guide.update(subject: aligned, stable: true, now: 0.5), .aligned)
        for t in 1...8 {
            XCTAssertEqual(guide.update(subject: subject(2.0 / 3 - 0.1 + 0.08), stable: true,
                                        now: Double(t)), .aligned)
        }
    }
    func testEdgesAskForSpace() {
        var guide = CompositionGuide()
        _ = guide.update(subject: subject(0.01), stable: true, now: 0)
        XCTAssertEqual(guide.update(subject: subject(0.01), stable: true, now: 0.6), .stepBack)
    }
    func testFrameThrottleAndNoCatchup() {
        var gate = FrameGate()
        XCTAssertTrue(gate.admit(now: 0, interval: 0.4))
        XCTAssertFalse(gate.admit(now: 0.1, interval: 0.4))
        XCTAssertTrue(gate.admit(now: 100, interval: 0.4))
        XCTAssertFalse(gate.admit(now: 100, interval: 0.4))
        XCTAssertFalse(gate.admit(now: 101, interval: .infinity))
        XCTAssertFalse(gate.admit(now: .nan, interval: 0.4))
    }
    func testCriticalHeatAndLowPower() {
        let critical = AnalysisPolicy.make(heat: .critical, lowPower: false, memoryPressure: false)
        XCTAssertFalse(critical.mayCapture)
        XCTAssertFalse(critical.saliencyEnabled)
        XCTAssertEqual(critical.interval, .infinity)
        let low = AnalysisPolicy.make(heat: .nominal, lowPower: true, memoryPressure: false)
        XCTAssertEqual(low.interval, 1)
        XCTAssertFalse(low.saliencyEnabled)
        XCTAssertFalse(AnalysisPolicy.make(heat: .serious, lowPower: false, memoryPressure: false).saliencyEnabled)
    }
    func testLevelProjectionAndFlatAim() {
        XCTAssertEqual(LevelMath.angle(gx: 0, gy: -1, clockwiseQuarterTurns: 0), 0)
        XCTAssertNil(LevelMath.angle(gx: 0.01, gy: 0.01, clockwiseQuarterTurns: 0))
        XCTAssertEqual(LevelMath.angle(gx: -1, gy: 0, clockwiseQuarterTurns: 1), 0)
        XCTAssertEqual(LevelMath.relative(-89, zero: 89), 2)
    }
}
