import XCTest
@testable import AppDNASDK

/// Placement selection read `audience_rules` as a dictionary only. When the console wrote the ARRAY
/// shape, the evaluator short-circuited to `true` — every paywall at the placement "matched", every
/// `priority` read 0, and the winner was whatever order the config dictionary iterated in.
final class PaywallPlacementResolverTests: XCTestCase {

    private func paywall(_ json: String) throws -> PaywallConfig {
        try JSONDecoder().decode(PaywallConfig.self, from: Data(json.utf8))
    }

    /// The deterministic proof: a single paywall whose ARRAY-shaped rules do not match the user must
    /// select NOTHING. Pre-fix this returned the paywall.
    func testArrayShapedRulesThatDoNotMatchSelectNothing() throws {
        let pw = try paywall(#"{"id":"pw_pro","placement":"main","audience_rules":[{"field":"plan","operator":"eq","value":"pro"}]}"#)

        let picked = PaywallPlacementResolver.pick(
            from: [pw],
            placement: "main",
            traits: ["plan": "free"]
        )

        XCTAssertNil(picked)
    }

    func testArrayShapedRulesThatMatchAreSelected() throws {
        let pw = try paywall(#"{"id":"pw_pro","placement":"main","audience_rules":[{"field":"plan","operator":"eq","value":"pro"}]}"#)

        let picked = PaywallPlacementResolver.pick(
            from: [pw],
            placement: "main",
            traits: ["plan": "pro"]
        )

        XCTAssertEqual(picked?.id, "pw_pro")
    }

    /// The real-world shape of the bug: a targeted paywall and a catch-all at the same placement. A
    /// free user must fall through to the catch-all, not get the pro-only paywall.
    func testNonMatchingTargetedPaywallFallsThroughToCatchAll() throws {
        let targeted = try paywall(#"{"id":"pw_pro","placement":"main","audience_rules":[{"field":"plan","operator":"eq","value":"pro"}]}"#)
        let catchAll = try paywall(#"{"id":"pw_default","placement":"main"}"#)

        let picked = PaywallPlacementResolver.pick(
            from: [targeted, catchAll],
            placement: "main",
            traits: ["plan": "free"]
        )

        XCTAssertEqual(picked?.id, "pw_default")
    }

    func testPlacementFilterExcludesOtherPlacements() throws {
        let other = try paywall(#"{"id":"pw_other","placement":"settings"}"#)
        XCTAssertNil(PaywallPlacementResolver.pick(from: [other], placement: "main", traits: [:]))
    }

    /// Object-shaped rules still carry a priority, and the highest one still wins regardless of the
    /// order the caller supplies.
    func testHighestPriorityMatchWins() throws {
        let low = try paywall(#"{"id":"pw_low","placement":"main","audience_rules":{"priority":1,"conditions":[{"field":"plan","operator":"eq","value":"free"}]}}"#)
        let high = try paywall(#"{"id":"pw_high","placement":"main","audience_rules":{"priority":10,"conditions":[{"field":"plan","operator":"eq","value":"free"}]}}"#)

        XCTAssertEqual(
            PaywallPlacementResolver.pick(from: [low, high], placement: "main", traits: ["plan": "free"])?.id,
            "pw_high"
        )
        XCTAssertEqual(
            PaywallPlacementResolver.pick(from: [high, low], placement: "main", traits: ["plan": "free"])?.id,
            "pw_high"
        )
    }
}
