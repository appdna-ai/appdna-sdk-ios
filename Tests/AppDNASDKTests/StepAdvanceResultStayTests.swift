import XCTest
@testable import AppDNASDK

/// Tests for `StepAdvanceResult.stay(message:)` — the new case added in
/// v1.0.60 for the "show success popup, don't advance, don't show error"
/// flow (e.g., forgot-password reset email confirmation).
final class StepAdvanceResultStayTests: XCTestCase {

    // MARK: - Enum case construction

    func testStayWithoutMessage() {
        let result: StepAdvanceResult = .stay()
        if case .stay(let message) = result {
            XCTAssertNil(message, "Default initializer should produce nil message")
        } else {
            XCTFail("Expected .stay case")
        }
    }

    func testStayWithMessage() {
        let result: StepAdvanceResult = .stay(message: "Reset email sent")
        if case .stay(let message) = result {
            XCTAssertEqual(message, "Reset email sent")
        } else {
            XCTFail("Expected .stay case")
        }
    }

    func testStayWithExplicitNilMessage() {
        let result: StepAdvanceResult = .stay(message: nil)
        if case .stay(let message) = result {
            XCTAssertNil(message)
        } else {
            XCTFail("Expected .stay case")
        }
    }

    func testStayWithEmptyMessageStillStaysSilent() {
        // Empty string should NOT show a banner — handleHookResult treats
        // empty string the same as nil to avoid an empty success banner.
        let result: StepAdvanceResult = .stay(message: "")
        if case .stay(let message) = result {
            XCTAssertEqual(message, "")
        } else {
            XCTFail("Expected .stay case")
        }
    }

    // MARK: - Distinct from other cases

    func testStayIsNotProceed() {
        let result: StepAdvanceResult = .stay()
        if case .proceed = result {
            XCTFail(".stay should not match .proceed")
        }
    }

    func testStayIsNotBlock() {
        // Critical semantic difference — .stay is NOT an error path. Must be
        // distinguishable from .block(message:) for renderer styling.
        let stayResult: StepAdvanceResult = .stay(message: "Reset email sent")
        let blockResult: StepAdvanceResult = .block(message: "Network error")

        var stayMatched = false
        var blockMatched = false

        if case .stay = stayResult { stayMatched = true }
        if case .block = blockResult { blockMatched = true }

        XCTAssertTrue(stayMatched)
        XCTAssertTrue(blockMatched)

        // And they shouldn't cross-match
        if case .block = stayResult {
            XCTFail(".stay must not pattern-match as .block")
        }
        if case .stay = blockResult {
            XCTFail(".block must not pattern-match as .stay")
        }
    }

    func testStayIsNotSkipTo() {
        let result: StepAdvanceResult = .stay()
        if case .skipTo = result {
            XCTFail(".stay should not match .skipTo")
        }
    }
}
