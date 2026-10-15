import XCTest
#if SWIFT_PACKAGE
@testable import CompositionCore
#else
@testable import FrameGuide
#endif

final class CameraLifecycleTests: XCTestCase {
    func testLatePermissionGrantDoesNotStartInBackground() {
        var intent = CameraStartIntent()
        XCTAssertTrue(intent.start(needsPermission: true))
        intent.stop()
        XCTAssertFalse(intent.resolved(granted: true))
        XCTAssertFalse(intent.wantsRunning)
    }
    func testRapidRepeatedStartsOnlyRequestPermissionOnce() {
        var intent = CameraStartIntent()
        XCTAssertTrue(intent.start(needsPermission: true))
        XCTAssertFalse(intent.start(needsPermission: true))
        XCTAssertFalse(intent.start(needsPermission: true))
        XCTAssertTrue(intent.resolved(granted: true))
    }
    func testForegroundCanResumeAfterPermissionAndStop() {
        var intent = CameraStartIntent()
        _ = intent.start(needsPermission: true); intent.stop()
        _ = intent.start(needsPermission: true)
        XCTAssertTrue(intent.resolved(granted: true))
        intent.stop(); XCTAssertFalse(intent.wantsRunning)
        XCTAssertFalse(intent.start(needsPermission: false))
        XCTAssertTrue(intent.wantsRunning)
    }
    func testDeniedPermissionClearsIntentAndPendingFlag() {
        var intent = CameraStartIntent()
        _ = intent.start(needsPermission: true)
        XCTAssertFalse(intent.resolved(granted: false))
        XCTAssertFalse(intent.wantsRunning)
        XCTAssertFalse(intent.authorizationPending)
    }
}
