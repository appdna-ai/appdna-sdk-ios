import XCTest
@testable import AppDNASDK

/// Gaps in `AudienceRuleEvaluator` that made rules pass VACUOUSLY — the worst possible failure mode
/// for a targeting engine, because "everyone matched" looks exactly like "the rules work" until you
/// read the numbers. Each test here fails on the pre-fix evaluator.
final class AudienceRuleGapsTests: XCTestCase {

    private func rule(_ json: String) throws -> AudienceRule {
        try JSONDecoder().decode(AudienceRule.self, from: Data(json.utf8))
    }

    private func anyCodable(_ json: String) throws -> AnyCodable {
        try JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
    }

    // MARK: - `field` alias

    /// The console writes `field`; only `trait` used to decode. A rule with `field` decoded to
    /// `trait == nil`, and `evaluateRule` returns true for a nil trait → the rule matched everyone.
    func testFieldAliasDecodesAsTrait() throws {
        let r = try rule(#"{"field":"plan","operator":"eq","value":"pro"}"#)
        XCTAssertEqual(r.trait, "plan")
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["plan": "pro"]))
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["plan": "free"]))
    }

    func testTraitKeyStillDecodes() throws {
        let r = try rule(#"{"trait":"plan","operator":"eq","value":"pro"}"#)
        XCTAssertEqual(r.trait, "plan")
    }

    // MARK: - `between`

    /// `between` was not implemented — it fell into `default: return true`.
    func testBetweenIsAClosedInterval() throws {
        let r = try rule(#"{"field":"days_since_install","operator":"between","min":3,"max":7}"#)
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["days_since_install": 7]))
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["days_since_install": 3]))
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["days_since_install": 5]))
    }

    /// The load-bearing half: out-of-range must be FALSE. Pre-fix this returned true.
    func testBetweenRejectsOutOfRange() throws {
        let r = try rule(#"{"field":"days_since_install","operator":"between","min":3,"max":7}"#)
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["days_since_install": 8]))
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["days_since_install": 2]))
    }

    /// A trait that isn't there (or isn't numeric) cannot be "between" anything.
    func testBetweenRejectsMissingOrNonNumericTrait() throws {
        let r = try rule(#"{"field":"days_since_install","operator":"between","min":3,"max":7}"#)
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: [:]))
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["days_since_install": "soon"]))
    }

    // MARK: - `in` / `not_in`

    /// `in` only matched [String] against a String trait, so an Int trait 1 vs values ["1","2"] was
    /// FALSE — and the `values` key didn't decode at all, so the list was empty.
    func testInCoercesIntTraitAgainstStringList() throws {
        let r = try rule(#"{"field":"tier","operator":"in","values":["1","2"]}"#)
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["tier": 1]))
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["tier": 3]))
    }

    func testNotInCoercesIntTraitAgainstStringList() throws {
        let r = try rule(#"{"field":"tier","operator":"not_in","values":["1","2"]}"#)
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["tier": 1]))
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["tier": 3]))
    }

    /// Legacy payloads put the list in `value`; both shapes must work.
    func testInAcceptsListUnderValueKey() throws {
        let r = try rule(#"{"trait":"tier","operator":"in","value":["1","2"]}"#)
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(ruleArray: [r], userTraits: ["tier": "2"]))
    }

    // MARK: - Array-shaped `audience_rules`

    /// The console persists `audience_rules` as an object OR a bare array. The array shape used to
    /// fall through the `as? [String: Any]` cast and return true — i.e. every entity matched every
    /// user. This is the same defect that made paywall placement selection arbitrary.
    func testArrayShapedRulesAreEvaluatedNotSkipped() throws {
        let rules = try anyCodable(#"[{"field":"plan","operator":"eq","value":"pro"}]"#)
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(rules: rules, traits: ["plan": "pro"]))
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(rules: rules, traits: ["plan": "free"]))
    }

    func testObjectShapedRulesStillEvaluate() throws {
        let rules = try anyCodable(#"{"priority":5,"match_mode":"any","conditions":[{"field":"plan","operator":"eq","value":"pro"},{"field":"tier","operator":"in","values":["1"]}]}"#)
        XCTAssertTrue(AudienceRuleEvaluator.evaluate(rules: rules, traits: ["plan": "free", "tier": 1]))
        XCTAssertFalse(AudienceRuleEvaluator.evaluate(rules: rules, traits: ["plan": "free", "tier": 9]))
        XCTAssertEqual(AudienceRuleEvaluator.priority(rules: rules), 5)
    }

    /// The array shape has nowhere to carry a priority, so it must sort as 0 rather than crash.
    func testArrayShapedRulesHaveZeroPriority() throws {
        let rules = try anyCodable(#"[{"field":"plan","operator":"eq","value":"pro"}]"#)
        XCTAssertEqual(AudienceRuleEvaluator.priority(rules: rules), 0)
    }
}
