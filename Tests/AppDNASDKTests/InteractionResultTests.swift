import XCTest
@testable import AppDNASDK

/// SPEC-419 EPIC-11 — pure logic of the interactive-state-contract result application.
final class InteractionResultTests: XCTestCase {

    func testMergesInputValuePatchesOverExisting() {
        let result = ElementInteractionResult(inputValuePatches: ["name": "Alex", "age": 25])
        let applied = applyInteractionResult(result, inputValues: ["name": "old", "city": "NYC"])
        XCTAssertEqual(applied.inputValues["name"] as? String, "Alex")  // patched
        XCTAssertEqual(applied.inputValues["age"] as? Int, 25)          // added
        XCTAssertEqual(applied.inputValues["city"] as? String, "NYC")   // untouched
        XCTAssertTrue(applied.fieldConfigOverrides.isEmpty)
        XCTAssertFalse(applied.advance)
    }

    func testExposesFieldConfigOverridesAndAdvance() {
        let result = ElementInteractionResult(
            fieldConfigPatches: ["cal": ["selected_days": [1, 2, 3]]],
            advance: true
        )
        let applied = applyInteractionResult(result, inputValues: [:])
        XCTAssertEqual(applied.fieldConfigOverrides["cal"]?["selected_days"] as? [Int], [1, 2, 3])
        XCTAssertTrue(applied.advance)
    }

    func testEmptyResultIsNoOp() {
        let applied = applyInteractionResult(ElementInteractionResult(), inputValues: ["k": "v"])
        XCTAssertEqual(applied.inputValues["k"] as? String, "v")
        XCTAssertTrue(applied.fieldConfigOverrides.isEmpty)
        XCTAssertFalse(applied.advance)
    }
}
