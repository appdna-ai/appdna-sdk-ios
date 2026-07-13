import XCTest
@testable import AppDNASDK

/// 🔴 USER A'S ONBOARDING ANSWERS SURVIVED THE SIGN-OUT AND RENDERED INTO USER B'S PAYWALL.
///
/// `SessionDataStore` is a PERSISTED process-global — `UserDefaults` here, `SharedPreferences` on
/// Android — holding three buckets: onboarding responses, computed data, session data. `AppDNA.reset()`
/// cleared identity, exposures, message session and survey session, and NEVER TOUCHED IT. Neither did
/// `shutdown()`. `clearAll()` existed on both platforms and had ZERO callers.
///
/// So on a shared device — a family tablet, a hot-desk phone, a demo unit, a resold handset — user B
/// could read user A's onboarding answers and structured location straight back out, via
/// `getOnboardingResponses()`, `session.get(_:)`, `getLocationData(fieldId:)`.
///
/// And worse than the read: `TemplateEngine.buildContext()` feeds all three buckets into the `{{…}}`
/// namespace, so A's answers RENDERED INTO B's paywall, onboarding and in-app-message copy. "Welcome
/// back, {{onboarding.first_name}}" — with the wrong name. It survived app restarts, because the store
/// is on disk. The file's own comment said the data was "not sensitive"; it is an email, a name and a
/// location.
///
/// These tests assert the LEAK IS CLOSED, not that a method was called: they write the data, reset, and
/// read back through the same surface a host (or the template engine) would use. A test asserting
/// `verify(clearAll)` would pass against a `clearAll()` that does nothing.
final class ResetClearsSessionDataTests: XCTestCase {

    private var store: SessionDataStore { SessionDataStore.shared }

    override func setUp() {
        super.setUp()
        store.clearAll()
    }

    override func tearDown() {
        store.clearAll()
        super.tearDown()
    }

    /// User A fills in an onboarding flow: an email, a name, a location. Real PII.
    private func signInAsUserAAndAnswerOnboarding() {
        // Responses are keyed by STEP id, each step holding its own field map — the shape the flow
        // manager persists on completion.
        store.setOnboardingResponses([
            "step_email": ["email": "alice@example.com"],
            "step_name": ["first_name": "Alice"],
            "step_goal": ["goal": "lose_weight"],
        ])
        store.mergeComputedData(["bmi": 22.4])
        store.setSessionData(key: "last_city", value: "Warsaw")
    }

    /// `reset()` dispatches onto the SDK's private serial queue, so the assertions have to wait for the
    /// work to land. The queue is not reachable from a test (`shared` is private, correctly), so this
    /// waits on the OBSERVABLE EFFECT rather than on an internal — which is the right thing to wait on
    /// anyway: it is exactly what a host would see.
    ///
    /// It deliberately does NOT assert here. If the clear never happens, this returns after the timeout
    /// and the real assertions below fail with a message about the leak — not with "timed out", which
    /// would say nothing about the bug.
    private func resetAndWait(timeout: TimeInterval = 2.0) {
        AppDNA.reset()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if store.onboardingResponses.isEmpty && store.computedData.isEmpty { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testResetClearsEveryBucketSoUserBCannotReadUserAsAnswers() {
        signInAsUserAAndAnswerOnboarding()

        // Sanity: the data really is there before the sign-out. Without this, "empty after reset" would
        // also pass against a store that never stored anything.
        XCTAssertEqual(store.onboardingResponses["step_email"]?["email"] as? String, "alice@example.com")
        XCTAssertEqual(store.getSessionData(key: "last_city") as? String, "Warsaw")

        resetAndWait()

        XCTAssertTrue(
            store.onboardingResponses.isEmpty,
            "user B can read user A's onboarding answers after A signed out"
        )
        XCTAssertTrue(
            store.computedData.isEmpty,
            "user B can read user A's computed data after A signed out"
        )
        XCTAssertNil(
            store.getSessionData(key: "last_city"),
            "user B can read user A's session data after A signed out"
        )
    }

    /// The bucket that mattered most, on its own: this is what the template engine reads. A stale
    /// `first_name` here does not merely leak — it PRINTS, in user B's paywall copy.
    func testAfterResetTheTemplateNamespaceIsEmpty() {
        signInAsUserAAndAnswerOnboarding()
        XCTAssertEqual(store.onboardingResponses["step_name"]?["first_name"] as? String, "Alice")

        resetAndWait()

        XCTAssertNil(
            store.onboardingResponses["step_name"]?["first_name"],
            "\"Welcome back, {{onboarding.first_name}}\" would still render Alice's name to user B"
        )
    }

    /// `shutdown()` is a LIFECYCLE stop, not a user change. Clearing a user's answers because the app is
    /// tearing down would be a different bug — the same person relaunches and their flow is gone. Pinned
    /// so a later tidy-up cannot quietly collapse the two.
    func testShutdownDoesNotClearSessionData() {
        signInAsUserAAndAnswerOnboarding()

        AppDNA.shutdown()

        XCTAssertEqual(
            store.onboardingResponses["step_email"]?["email"] as? String,
            "alice@example.com",
            "shutdown() erased the user's own onboarding answers — it is not a sign-out"
        )
    }
}
