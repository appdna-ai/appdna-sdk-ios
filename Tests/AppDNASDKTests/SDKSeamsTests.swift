import XCTest
@testable import AppDNASDK

/// Coverage for the logic that used to live INSIDE SwiftUI closures and manager privates — i.e. code
/// that no test could reach, which is why the shared-fixture runner mirrored it instead of calling
/// it. Each symbol below is the production path; the views now call these.
final class SDKSeamsTests: XCTestCase {

    // MARK: - Event envelope observability

    /// `EventTracker.track` builds the envelope every SDK event ships in, then hands it to a concrete
    /// `EventQueue`. Without a sink there is no way to assert what the SDK actually emitted.
    func testEventSinkReceivesTheBuiltEnvelope() {
        let keychain = KeychainStore(service: "ai.appdna.sdk.test.\(UUID().uuidString)")
        let tracker = EventTracker(identityManager: IdentityManager(keychainStore: keychain))

        var seen: [SDKEvent] = []
        tracker.eventSink = { seen.append($0) }

        tracker.track(event: "paywall_view", properties: ["paywall_id": "pw_1"])

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.event_name, "paywall_view")
        XCTAssertEqual(seen.first?.properties?["paywall_id"]?.value as? String, "pw_1")
    }

    /// Consent is enforced before the envelope is built, so a dropped event must never reach the sink.
    func testEventSinkSeesNothingWhenConsentIsDenied() {
        let keychain = KeychainStore(service: "ai.appdna.sdk.test.\(UUID().uuidString)")
        let tracker = EventTracker(identityManager: IdentityManager(keychainStore: keychain))
        tracker.setInitialConsent(analytics: false)

        var seen: [SDKEvent] = []
        tracker.eventSink = { seen.append($0) }

        tracker.track(event: "paywall_view", properties: nil)

        XCTAssertTrue(seen.isEmpty)
    }

    // MARK: - Social login dual-emit

    /// The email provider dual-emits `email_login` + the deprecated `social_login`. A silent
    /// regression to a single emit breaks every host still switching on `social_login`.
    func testEmailProviderDualEmits() {
        let emits = SocialLoginActionDispatcher.actions(forProviderType: "email")
        XCTAssertEqual(emits.map(\.action), ["email_login", "social_login"])
        XCTAssertEqual(emits.map { $0.value ?? "" }, ["email", "email"])
    }

    func testNonEmailProviderEmitsSocialLoginOnce() {
        let emits = SocialLoginActionDispatcher.actions(forProviderType: "apple")
        XCTAssertEqual(emits.count, 1)
        XCTAssertEqual(emits[0].action, "social_login")
        XCTAssertEqual(emits[0].value, "apple")
    }

    // MARK: - Webhook response parsing

    func testWebhookProceedWithData() {
        let result = WebhookResponseParser.parse(
            Data(#"{"action":"proceed","data":{"score":42}}"#.utf8),
            errorText: nil
        )
        guard case let .proceedWithData(data) = result else { return XCTFail("expected proceedWithData, got \(result)") }
        XCTAssertEqual(data["score"] as? Int, 42)
    }

    func testWebhookSkipToWithoutTargetProceeds() {
        let result = WebhookResponseParser.parse(Data(#"{"action":"skip_to"}"#.utf8), errorText: nil)
        guard case .proceed = result else { return XCTFail("expected proceed, got \(result)") }
    }

    func testWebhookBlockPrefersServerMessageOverConfiguredErrorText() {
        let result = WebhookResponseParser.parse(
            Data(#"{"action":"block","message":"Email already in use"}"#.utf8),
            errorText: "Something went wrong"
        )
        guard case let .block(message) = result else { return XCTFail("expected block, got \(result)") }
        XCTAssertEqual(message, "Email already in use")
    }

    /// Garbage in must block the user, never advance them.
    func testWebhookMalformedBodyBlocksWithConfiguredErrorText() {
        let result = WebhookResponseParser.parse(Data("not json".utf8), errorText: "Try again")
        guard case let .block(message) = result else { return XCTFail("expected block, got \(result)") }
        XCTAssertEqual(message, "Try again")
    }

    /// These names land in BigQuery on `onboarding_hook_*` events — they cannot drift.
    func testStepAdvanceResultWireNames() {
        XCTAssertEqual(StepAdvanceResultNaming.name(.proceed), "proceed")
        XCTAssertEqual(StepAdvanceResultNaming.name(.proceedWithData([:])), "proceed_with_data")
        XCTAssertEqual(StepAdvanceResultNaming.name(.block(message: "x")), "block")
        XCTAssertEqual(StepAdvanceResultNaming.name(.stay(message: nil)), "stay")
        XCTAssertEqual(StepAdvanceResultNaming.name(.skipTo(stepId: "s")), "skip_to")
        XCTAssertEqual(StepAdvanceResultNaming.name(.skipToWithData(stepId: "s", data: [:])), "skip_to")
    }

    // MARK: - Step config overrides

    func testStepConfigOverrideReplacesOnlyAuthoredFields() throws {
        let config = try JSONDecoder().decode(
            StepConfig.self,
            from: Data(#"{"title":"Original","subtitle":"Sub","cta_text":"Continue"}"#.utf8)
        )
        let override = StepConfigOverride(title: "Overridden", ctaText: "Go")

        let merged = StepConfigOverrideMerger.apply(override, to: config)

        XCTAssertEqual(merged.title, "Overridden")
        XCTAssertEqual(merged.cta_text, "Go")
        XCTAssertEqual(merged.subtitle, "Sub") // untouched
    }

    func testNoOverrideReturnsConfigUnchanged() throws {
        let config = try JSONDecoder().decode(StepConfig.self, from: Data(#"{"title":"Original"}"#.utf8))
        XCTAssertEqual(StepConfigOverrideMerger.apply(nil, to: config).title, "Original")
    }

    // MARK: - In-app message presentation gate

    func testMessageGateAllowsByDefault() {
        XCTAssertTrue(MessagePresentationGate.shouldPresent(
            messageId: "m1", isPresenting: false, runtimeLocked: false, delegate: nil
        ))
    }

    func testMessageGateBlocksWhilePresentingOrRuntimeLocked() {
        XCTAssertFalse(MessagePresentationGate.shouldPresent(
            messageId: "m1", isPresenting: true, runtimeLocked: false, delegate: nil
        ))
        XCTAssertFalse(MessagePresentationGate.shouldPresent(
            messageId: "m1", isPresenting: false, runtimeLocked: true, delegate: nil
        ))
    }

    func testMessageGateHonorsHostVeto() {
        let host = VetoingMessageDelegate(vetoed: ["m_blocked"])
        XCTAssertFalse(MessagePresentationGate.shouldPresent(
            messageId: "m_blocked", isPresenting: false, runtimeLocked: false, delegate: host
        ))
        XCTAssertTrue(MessagePresentationGate.shouldPresent(
            messageId: "m_allowed", isPresenting: false, runtimeLocked: false, delegate: host
        ))
    }
}

private final class VetoingMessageDelegate: AppDNAInAppMessageDelegate {
    private let vetoed: Set<String>
    init(vetoed: Set<String>) { self.vetoed = vetoed }
    func shouldShowMessage(messageId: String) -> Bool { !vetoed.contains(messageId) }
}
