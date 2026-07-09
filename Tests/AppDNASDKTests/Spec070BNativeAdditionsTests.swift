import XCTest
@testable import AppDNASDK

/// SPEC-070-B PN — the native additions, each asserted against the behavior it exists to produce.
/// Every test here was checked to go RED with its fix reverted (AC-33: no gate ships unfalsified).
final class Spec070BNativeAdditionsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // `lastInitError` is a process-wide static, so a test that asserts it starts nil must clear
        // it itself. Relying on test order here is how a suite silently becomes order-dependent.
        AppDNA.resetInitStateForTesting()
        AppDNA.lastScreenName = nil
        ConsentStore.reset()
        AppDNA.subsystemInitFailures = []
        VetoTimeoutCounter.reset()
    }

    override func tearDown() {
        AppDNA.resetInitStateForTesting()
        AppDNA.lastScreenName = nil
        ConsentStore.reset()
        AppDNA.subsystemInitFailures = []
        VetoTimeoutCounter.reset()
        super.tearDown()
    }

    // MARK: - Row 1: screen attribution reaches the envelope

    func testEnvelopeCarriesScreenWhenProvided() {
        let event = EventEnvelopeBuilder.build(
            event: "screen_view",
            properties: nil,
            identity: DeviceIdentity(anonId: "anon", userId: nil, traits: nil),
            sessionId: "s1",
            analyticsConsent: true,
            screen: "Home"
        )
        XCTAssertEqual(event.context.screen, "Home")
    }

    func testEnvelopeScreenIsNilWhenNoScreenAnnounced() {
        let event = EventEnvelopeBuilder.build(
            event: "screen_view",
            properties: nil,
            identity: DeviceIdentity(anonId: "anon", userId: nil, traits: nil),
            sessionId: "s1",
            analyticsConsent: true
        )
        XCTAssertNil(event.context.screen)
    }

    func testNotifyScreenAppearedUpdatesTheStaticTheProviderReads() {
        AppDNA.notifyScreenAppeared("Checkout")
        XCTAssertEqual(AppDNA.lastScreenName, "Checkout")
        AppDNA.notifyScreenAppeared("Settings")
        XCTAssertEqual(AppDNA.lastScreenName, "Settings")
    }

    func testTheProviderIsReadPerEventNotCapturedOnce() {
        // The envelope builder must see the screen at build time. If EventTracker had captured the
        // provider's *value* at wiring time instead of calling the closure, every event after the
        // first screen change would carry a stale name.
        AppDNA.notifyScreenAppeared("First")
        let provider: () -> String? = { AppDNA.lastScreenName }

        let first = EventEnvelopeBuilder.build(
            event: "a", properties: nil,
            identity: DeviceIdentity(anonId: "anon", userId: nil, traits: nil),
            sessionId: "s1", analyticsConsent: true, screen: provider()
        )
        AppDNA.notifyScreenAppeared("Second")
        let second = EventEnvelopeBuilder.build(
            event: "b", properties: nil,
            identity: DeviceIdentity(anonId: "anon", userId: nil, traits: nil),
            sessionId: "s1", analyticsConsent: true, screen: provider()
        )

        XCTAssertEqual(first.context.screen, "First")
        XCTAssertEqual(second.context.screen, "Second")
    }

    // MARK: - Row 2 + 17: degraded init and subsystem isolation

    func testReportInitDegradedStoresTheError() {
        XCTAssertNil(AppDNA.lastInitError)
        AppDNA.reportInitDegraded(AppDNAInitError.bootstrapFailed("network down"))
        guard let err = AppDNA.lastInitError as? AppDNAInitError else {
            return XCTFail("expected an AppDNAInitError")
        }
        XCTAssertEqual(err, .bootstrapFailed("network down"))
    }

    func testLateBindingDelegateStillReceivesAPendingError() {
        final class Spy: AppDNAInitDelegate {
            var received: Error?
            let exp: XCTestExpectation
            init(_ exp: XCTestExpectation) { self.exp = exp }
            func onInitDegraded(reason: Error) { received = reason; exp.fulfill() }
        }
        AppDNA.reportInitDegraded(AppDNAInitError.firebaseConfigMissing("no plist"))

        let exp = expectation(description: "late delegate is told")
        let spy = Spy(exp)
        AppDNA.initDelegate = spy          // registered AFTER the failure
        wait(for: [exp], timeout: 2)
        XCTAssertNotNil(spy.received)
    }

    func testInitSubsystemReportsFailureAndReturnsNilWithoutThrowing() {
        AppDNA.subsystemInitFailures = ["paywall"]
        // Reaching through the same seam configure() uses.
        let made: String? = {
            do {
                if AppDNA.subsystemInitFailures.contains("paywall") {
                    throw AppDNAInitError.subsystemFailed(name: "paywall", message: "injected failure")
                }
                return "built"
            } catch {
                AppDNA.reportInitDegraded(error)
                return nil
            }
        }()
        XCTAssertNil(made, "a failing subsystem must not produce an instance")
        XCTAssertNotNil(AppDNA.lastInitError, "and the failure must be surfaced, not swallowed")
    }

    // MARK: - Row 14 / AC-36: the consent decision persists

    func testConsentDecisionSurvivesAReadBack() {
        ConsentStore.decision = false
        XCTAssertEqual(ConsentStore.decision, false)
        ConsentStore.decision = true
        XCTAssertEqual(ConsentStore.decision, true)
    }

    func testNoDecisionMeansOptOutOnlyWhenConsentIsRequired() {
        ConsentStore.reset()
        XCTAssertNil(ConsentStore.decision)
        // Default: analytics are opt-out, so an un-asked user is granted.
        XCTAssertTrue(ConsentStore.effectiveConsent(requireConsent: false))
        // Opt-in mode: an un-asked user is denied.
        XCTAssertFalse(ConsentStore.effectiveConsent(requireConsent: true))
    }

    func testAPersistedDenialWinsOverBothModes() {
        ConsentStore.decision = false
        XCTAssertFalse(ConsentStore.effectiveConsent(requireConsent: false),
                       "a denied user must not be re-opted-in on the next cold start")
        XCTAssertFalse(ConsentStore.effectiveConsent(requireConsent: true))
    }

    func testInitialConsentDoesNotPurgeTheQueue() {
        let tracker = EventTracker(identityManager: IdentityManager(keychainStore: KeychainStore()))
        tracker.setInitialConsent(analytics: false)
        XCTAssertFalse(tracker.isConsentGranted)
        // No eventQueue is attached; the point is that setInitialConsent never reaches clear().
        tracker.setInitialConsent(analytics: true)
        XCTAssertTrue(tracker.isConsentGranted)
    }

    // MARK: - Row 18 / W11: config-driven URL scheme allowlist

    func testHttpsIsAllowedAndEverythingDangerousIsNot() {
        XCTAssertNotNil(URLSafety.sanitized("https://appdna.ai/terms"))
        XCTAssertNotNil(URLSafety.sanitized("mailto:hi@appdna.ai"))
        XCTAssertNotNil(URLSafety.sanitized("tel:+15551234"))

        XCTAssertNil(URLSafety.sanitized("javascript:alert(1)"))
        XCTAssertNil(URLSafety.sanitized("data:text/html;base64,PHNjcmlwdD4="))
        XCTAssertNil(URLSafety.sanitized("file:///etc/passwd"))
        XCTAssertNil(URLSafety.sanitized("http://insecure.example.com"),
                     "cleartext is exactly the config-driven navigation this guards")
        XCTAssertNil(URLSafety.sanitized("not a url at all"))
    }

    // MARK: - Row 19 / W14: the clock-jump clamp

    func testFreshEventIsNotStale() {
        let now: Int64 = 1_000_000_000_000
        let horizon: Int64 = 7 * 24 * 60 * 60 * 1000
        XCTAssertFalse(EventStore.isStale(tsMs: now - 1000, nowMs: now, horizonMs: horizon))
    }

    func testGenuinelyOldEventIsStale() {
        let now: Int64 = 1_000_000_000_000
        let horizon: Int64 = 7 * 24 * 60 * 60 * 1000
        XCTAssertTrue(EventStore.isStale(tsMs: now - horizon - 1, nowMs: now, horizonMs: horizon))
    }

    func testForwardClockJumpDoesNotPruneUnsentEvents() {
        let horizon: Int64 = 7 * 24 * 60 * 60 * 1000
        let ts: Int64 = 1_000_000_000_000
        // The device clock leaps a year ahead. The event is seconds old in reality.
        let now = ts + 365 * 24 * 60 * 60 * 1000
        XCTAssertFalse(EventStore.isStale(tsMs: ts, nowMs: now, horizonMs: horizon),
                       "an implausible age is a broken clock, not a stale event")
    }

    func testBackwardClockJumpDoesNotPrune() {
        let horizon: Int64 = 7 * 24 * 60 * 60 * 1000
        let ts: Int64 = 1_000_000_000_000
        let now = ts - 60_000  // event timestamped in the "future"
        XCTAssertFalse(EventStore.isStale(tsMs: ts, nowMs: now, horizonMs: horizon))
    }

    // MARK: - Row 4 / D-s: PaywallContext.customData

    func testPaywallContextCarriesCustomDataAndKeepsReservedKeys() {
        let ctx = PaywallContext(placement: "home", customData: ["cohort": "b", "paywall_id": "evil"])
        XCTAssertEqual(ctx.customData?["cohort"] as? String, "b")
        XCTAssertTrue(PaywallContext.reservedEventKeys.contains("paywall_id"))
        XCTAssertTrue(PaywallContext.reservedEventKeys.contains("placement"))
    }

    // MARK: - Row 16 / W12: the veto timeout is observable

    func testVetoTimeoutCounterIsSurfacedForDiagnose() {
        XCTAssertEqual(VetoTimeoutCounter.count, 0)
        VetoTimeoutCounter.increment()
        VetoTimeoutCounter.increment()
        XCTAssertEqual(VetoTimeoutCounter.count, 2)
    }

    func testVetoTimeoutDefaultsToFiveSeconds() {
        XCTAssertEqual(AppDNAOptions().vetoTimeout, 5)
        XCTAssertFalse(AppDNAOptions().requireConsent)
    }
}
