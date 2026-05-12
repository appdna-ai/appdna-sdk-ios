import XCTest
@testable import AppDNASDK

/// SPEC-403 — paywall_trigger skip-target resolver chain tests.
///
/// The actual resolver lives inside `presentPaywallTrigger` (private to
/// OnboardingRenderer.swift), wired into a Task closure that calls
/// `routeOutcome(onSubscribedSkipTarget ?? onSuccessTarget, "continue",
/// "user_already_subscribed")`. We can't invoke that closure directly from
/// a unit test (no exposed seam), so this test file mirrors the resolver
/// as a pure function and asserts the chain produces the expected first
/// argument to `routeOutcome` for each input.
///
/// End-to-end behavior (resolver → routeOutcome → flowCompleted vs. edge
/// follow vs. specific target) is covered by the shared behavioral
/// fixtures at `packages/sdk-shared-fixtures/billing/`:
///   - onboarding_paywall_skip_to_end.fixture.json
///   - onboarding_paywall_skip_backcompat.fixture.json
/// loaded by `SharedFixtureTests.swift` and the equivalent Android/Flutter/RN
/// runners.
final class PaywallTriggerSkipTargetTests: XCTestCase {

    /// Pure mirror of `presentPaywallTrigger`'s resolver chain on line
    /// ~1274 after SPEC-403:
    ///
    ///     routeOutcome(onSubscribedSkipTarget ?? onSuccessTarget,
    ///                  "continue", "user_already_subscribed")
    ///
    /// `routeOutcome`'s first param has signature `(String?, String, String)
    /// -> Void`. The resolver may produce `nil`, in which case the second
    /// `defaultBehavior` arg (`"continue"`) kicks in. This helper returns
    /// the EFFECTIVE first arg (post resolver, pre default-behavior fallback).
    private func resolveSkipTarget(onSubscribedSkipTarget: String?, onSuccessTarget: String?) -> String? {
        // Mirror the SDK ternaries: empty string → nil before resolver.
        let resolvedSubSkip = (onSubscribedSkipTarget?.isEmpty == false) ? onSubscribedSkipTarget : nil
        let resolvedSuccess = (onSuccessTarget?.isEmpty == false) ? onSuccessTarget : nil
        return resolvedSubSkip ?? resolvedSuccess
    }

    /// Case 1 — explicit on_subscribed_skip_target wins.
    func testResolverPicksOnSubscribedSkipTargetWhenSet() {
        let resolved = resolveSkipTarget(
            onSubscribedSkipTarget: "complete_flow",
            onSuccessTarget: "step_some_other"
        )
        XCTAssertEqual(resolved, "complete_flow")
    }

    /// Case 2 — back-compat: empty on_subscribed_skip_target falls back to
    /// on_success_target (SPEC-401 1.0.61 workaround behavior preserved).
    func testResolverFallsBackToOnSuccessTargetWhenSkipTargetEmpty() {
        let resolved = resolveSkipTarget(
            onSubscribedSkipTarget: "",
            onSuccessTarget: "complete_flow"
        )
        XCTAssertEqual(resolved, "complete_flow")
    }

    func testResolverFallsBackToOnSuccessTargetWhenSkipTargetNil() {
        let resolved = resolveSkipTarget(
            onSubscribedSkipTarget: nil,
            onSuccessTarget: "step_welcome_back"
        )
        XCTAssertEqual(resolved, "step_welcome_back")
    }

    /// Case 3 — legacy: both empty → nil → routeOutcome falls through to
    /// its `defaultBehavior` argument ("continue") and follows the edge.
    /// This is the pre-SPEC-403 behavior, preserved for back-compat with
    /// existing flows authored before SPEC-403 ships.
    func testResolverReturnsNilWhenBothEmptyOrNil() {
        XCTAssertNil(resolveSkipTarget(onSubscribedSkipTarget: nil, onSuccessTarget: nil))
        XCTAssertNil(resolveSkipTarget(onSubscribedSkipTarget: "", onSuccessTarget: ""))
        XCTAssertNil(resolveSkipTarget(onSubscribedSkipTarget: "", onSuccessTarget: nil))
        XCTAssertNil(resolveSkipTarget(onSubscribedSkipTarget: nil, onSuccessTarget: ""))
    }

    /// Case 4 — author opts into chain-of-paywalls via explicit "continue".
    /// SPEC-403 lets authors keep the legacy edge-follow behavior; the
    /// dropdown surfaces it as "Follow downstream edge".
    func testResolverPicksExplicitContinue() {
        let resolved = resolveSkipTarget(
            onSubscribedSkipTarget: "continue",
            onSuccessTarget: nil
        )
        XCTAssertEqual(resolved, "continue")
    }

    /// Case 5 — author picks a specific node id (e.g., a "welcome back"
    /// screen for subscribed users that's different from the post-purchase
    /// target).
    func testResolverPicksSpecificNodeId() {
        let resolved = resolveSkipTarget(
            onSubscribedSkipTarget: "step_welcome_back",
            onSuccessTarget: "step_thank_you"
        )
        XCTAssertEqual(resolved, "step_welcome_back")
    }
}
