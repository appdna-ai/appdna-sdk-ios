import XCTest
@testable import AppDNASDK

/// 🔴 A FAILED LOGIN COUNTED AS A COMPLETED STEP.
///
/// `onboarding_step_completed` was emitted the moment the user tapped the button — BEFORE the hook had
/// decided anything. But on a hook step, the hook is what decides whether the step completes. A `login`
/// step whose delegate answers `.block("Wrong password")` does not complete: the user stays exactly
/// where they were, looking at the same step. The event had already gone out.
///
/// So a user who mistypes their password three times emits FOUR completions of a step they never
/// completed, and the successful fourth attempt makes five.
///
/// The metric this corrupts is the one the product is sold on — onboarding step-completion and funnel
/// conversion. And it over-counts worst precisely at the credential step, the step users actually FAIL
/// at, which means the flows that convert worst are the ones that look healthiest.
///
/// The rule now lives on the pure state machine (`Navigation.completesStep`) rather than in either
/// renderer, so both platforms answer the question identically and a test can ask it without a host.
/// These tests drive `OnboardingAdvance.apply` with real hook results and assert on the navigation it
/// produces — not on the enum in isolation, which would prove only that `.stay` is spelled correctly.
final class StepCompletionRequiresAdvanceTests: XCTestCase {

    private func flow(stepCount: Int = 3) -> OnboardingFlowConfig {
        let steps = (0..<stepCount).map { i in
            """
            { "id": "step_\(i)", "type": "question", "config": {} }
            """
        }.joined(separator: ",")
        let json = """
        { "id": "flow_1", "name": "Test", "steps": [\(steps)] }
        """.data(using: .utf8)!
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(OnboardingFlowConfig.self, from: json)
    }

    private func navigation(for result: StepAdvanceResult) -> OnboardingAdvance.Navigation {
        OnboardingAdvance.apply(
            result: result,
            flow: flow(),
            currentIndex: 0,
            responses: [:],
            configOverrides: [:],
            previousStepId: nil
        ).navigation
    }

    /// The one that cost us the funnel: the host said no, so nothing completed.
    func testABlockedHookDoesNotCompleteTheStep() {
        let nav = navigation(for: .block(message: "Wrong password"))
        XCTAssertFalse(
            nav.completesStep,
            "a BLOCKED hook counted as a completed step — the user typed the wrong password, stayed " +
            "on the credential step, and the funnel recorded a completion anyway"
        )
    }

    /// `.stay` is the same story wearing a friendlier face — "we emailed you a reset link", the user is
    /// still on the step. It must not complete either.
    func testAStayDoesNotCompleteTheStep() {
        XCTAssertFalse(navigation(for: .stay(message: "Check your email")).completesStep)
        XCTAssertFalse(navigation(for: .stay()).completesStep)
    }

    /// ...and the converse, which is what stops this fix from becoming an UNDER-count: every outcome
    /// that actually leaves the step MUST complete it. A fix that silenced the event entirely would
    /// pass the two tests above and destroy the funnel in the other direction.
    func testEveryAdvancingOutcomeCompletesTheStep() {
        XCTAssertTrue(navigation(for: .proceed).completesStep, "a plain advance must complete the step")
        XCTAssertTrue(
            navigation(for: .proceedWithData(["plan": "pro"])).completesStep,
            "an advance carrying hook data must complete the step"
        )
        XCTAssertTrue(
            navigation(for: .skipTo(stepId: "step_2")).completesStep,
            "skipping onward still LEAVES the step — it completed"
        )
        XCTAssertTrue(
            navigation(for: .skipToWithData(stepId: "step_2", data: ["x": 1])).completesStep,
            "skipping onward with data still leaves the step"
        )
    }

    /// Reaching the end of the flow completes the final step. Pinned because "completeFlow" is the one
    /// navigation that is neither a `goToIndex` nor a `stay`, and an `if case .goToIndex` written in
    /// haste would silently drop the LAST step out of every funnel.
    func testCompletingTheFlowCompletesItsFinalStep() {
        let nav = OnboardingAdvance.apply(
            result: .proceed,
            flow: flow(stepCount: 1),
            currentIndex: 0,
            responses: [:],
            configOverrides: [:],
            previousStepId: nil
        ).navigation

        if case .completeFlow = nav {} else {
            return XCTFail("expected the flow to complete from its only step; got \(nav)")
        }
        XCTAssertTrue(nav.completesStep, "the final step of a flow completed and was not counted")
    }
}
