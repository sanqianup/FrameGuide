import XCTest
#if SWIFT_PACKAGE
@testable import CompositionCore
#else
@testable import FrameGuide
#endif

/// All responses here are synthetic. These tests never contact a provider or use credentials.
final class CloudContractTests: XCTestCase {
    private let valid = """
    {"advice":"略微降低机位","tone":{"exposureEV":0.1,"saturation":1.02,"warmth":0.02,"contrast":1.01}}
    """
    private func envelope(_ content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    }
    func testSyntheticValidResponse() throws {
        let advice = try CloudContract.advice(from: envelope(valid))
        XCTAssertEqual(advice.advice, "略微降低机位")
        XCTAssertEqual(advice.tone.exposureEV, 0.1)
    }
    func testSyntheticRejectsOutOfRange() throws {
        let invalid = valid.replacingOccurrences(of: "0.1,", with: "4.0,")
        XCTAssertThrowsError(try CloudContract.advice(from: envelope(invalid)))
    }
    func testSyntheticRejectsProseAndMarkdown() throws {
        XCTAssertThrowsError(try CloudContract.advice(from: envelope("```json\n\(valid)\n```")))
        XCTAssertThrowsError(try CloudContract.advice(from: envelope("照片已经完美修复！")))
    }
    func testSyntheticRejectsMissingAndExtraFields() throws {
        XCTAssertThrowsError(try CloudContract.advice(from: envelope("{\"advice\":\"test\"}")))
        let extra = valid.replacingOccurrences(of: "\"tone\":", with: "\"retouchFace\":true,\"tone\":")
        XCTAssertThrowsError(try CloudContract.advice(from: envelope(extra)))
    }
    func testSyntheticRejectsEmptyAndOversizedEnvelopes() throws {
        XCTAssertThrowsError(try CloudContract.advice(from: Data("{\"choices\":[]}".utf8)))
        XCTAssertThrowsError(try CloudContract.advice(from: Data(repeating: 32, count: 1_000_001)))
    }
    func testEndpointRejectsCredentialsHTTPAndQuery() throws {
        for url in ["http://example.com/v1/chat/completions", "https://key@example.com/v1/chat/completions",
                    "https://example.com/v1?key=secret", "https://example.com/", "file:///tmp/photo", "https://example.com/v1#token"] {
            XCTAssertThrowsError(try CloudContract.endpoint(url))
        }
        XCTAssertEqual(try CloudContract.endpoint("https://api.xiaomimimo.com/v1/chat/completions").host, "api.xiaomimimo.com")
    }
    func testSingleRequestAndStaleResponseRejection() throws {
        var gate = RequestGate()
        let photo = UUID(), other = UUID()
        let first = try XCTUnwrap(gate.begin(photo: photo))
        XCTAssertNil(gate.begin(photo: other))
        XCTAssertFalse(gate.accepts(first, photo: other))
        gate.cancel()
        let second = try XCTUnwrap(gate.begin(photo: other))
        XCTAssertFalse(gate.accepts(first, photo: photo))
        gate.finish(first) // an old completion must not release a new request
        XCTAssertTrue(gate.accepts(second, photo: other))
        gate.finish(second)
        XCTAssertNil(gate.active)
    }
    func testToneRejectsNonFiniteAndAllowsIdentity() {
        XCTAssertTrue(ToneRecipe().isSafe)
        XCTAssertTrue(ToneRecipe.natural.isSafe)
        XCTAssertFalse(ToneRecipe(exposureEV: .infinity).isSafe)
        XCTAssertFalse(ToneRecipe(saturation: .nan).isSafe)
    }
    func testFrontCameraPanDirection() {
        XCTAssertEqual(Guidance.panRight.cameraAdvice(mirrored: true), .panLeft)
        XCTAssertEqual(Guidance.panLeft.cameraAdvice(mirrored: true), .panRight)
        XCTAssertEqual(Guidance.tiltUp.cameraAdvice(mirrored: true), .tiltUp)
        XCTAssertEqual(Guidance.panLeft.cameraAdvice(mirrored: false), .panLeft)
    }
}
