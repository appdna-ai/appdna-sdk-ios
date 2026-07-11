// SharedFixtureTests.swift
//
// Cross-platform behavioral fixture runner for iOS — SPEC-070-0 §3.2 + §3.3 step 4.
//
// Loads every `*.fixture.json` under `packages/sdk-shared-fixtures/` whose `platforms` list includes
// `ios`, drives the action THROUGH REAL SDK CODE, and asserts the observable outcome
// (events / delegate_calls / state_after / errors) against the fixture's `expect` block.
//
// WHAT "REAL" MEANS HERE
// ---------------------
// The previous version of this file did `@testable import AppDNASDK` and then used ZERO SDK symbols:
// every driver re-implemented the SDK's rules inside the test and asserted the re-implementation
// matched the fixture. You could have deleted the whole iOS SDK and this suite stayed green. It also
// carried a `knownDriverGaps` skiplist and a soft-skip that PASSED any action kind it had no driver
// for. `pnpm check:fixture-runner-skips` now bans all three.
//
// The rule this file follows:
//
//   Every value the fixture is actually testing — an audience match, a step-advance result name, a
//   webhook discriminator, a billing error type, a paywall skip decision, an experiment resolution, a
//   parsed DTO field, a measurement conversion, a push payload — is produced by a REAL SDK symbol.
//   Events flow through the REAL `EventTracker` (so the envelope, consent gate and screen context are
//   the SDK's), captured via `EventTracker.eventSink`.
//
//   Where the SDK's EMISSION SITE is unreachable from a test (it lives inside a SwiftUI view's private
//   closure, or behind StoreKit), the driver feeds the REAL decision into the REAL EventTracker using
//   the SDK's own event names and property keys, and says so in a comment marked
//   "EMISSION SITE NOT EXTRACTED". Those comments are the list of seams still to extract.
//
//   An action kind with NO driver is an XCTFail, never a skip. A `state_after` key that no real SDK
//   call produced is an XCTFail, never an omission. A fixture that asserts behaviour this SDK does not
//   have FAILS, loudly, with the reason — it is not skipped and it is not mirrored.
//
// FIXTURE PATH RESOLUTION
// -----------------------
//   1. `APPDNA_SDK_FIXTURES_DIR` env var (CI sets this absolute path)
//   2. Walk up from `#filePath` until `packages/sdk-shared-fixtures/` is found
//   3. Hardcoded codespace fallback
//
// © 2026 AppDNA AI, Inc.

import Foundation
import XCTest
@testable import AppDNASDK

final class SharedFixtureTests: XCTestCase {

    // MARK: - Fixture model

    /// Lightweight peek to read `category` without requiring `action` — lets the loader skip the
    /// fixture families that carry no `action` (they drive their own runners).
    struct FixtureHeader: Decodable {
        let category: String
    }

    struct Fixture: Decodable {
        let id: String
        let category: String
        let description: String
        let spec_refs: [String]?
        let platforms: [String]
        let setup: Setup
        let action: Action
        let expect: Expect
    }

    struct Setup: Decodable {
        let config: AnyJSON?
        let user_traits: AnyJSON?
        let session_data: AnyJSON?
        let experiment_assignments: AnyJSON?
        let remote_config: AnyJSON?
    }

    struct Action: Decodable {
        let kind: String
        let raw: [String: AnyJSON]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let blob = try container.decode(AnyJSON.self)
            guard case let .object(dict) = blob,
                  case let .string(kind)? = dict["kind"] else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "action.kind missing or not a string"
                )
            }
            self.kind = kind
            self.raw = dict
        }
    }

    struct Expect: Decodable {
        let events: [ExpectedEvent]?
        let delegate_calls: [ExpectedDelegateCall]?
        let state_after: AnyJSON?
        let errors: [ExpectedError]?
    }

    struct ExpectedEvent: Decodable {
        let name: String
        let properties: AnyJSON?
    }

    struct ExpectedDelegateCall: Decodable {
        let name: String
        let args: AnyJSON?
        let returns: AnyJSON?
    }

    struct ExpectedError: Decodable {
        let type: String
        let message: String?
    }

    // MARK: - AnyJSON

    indirect enum AnyJSON: Decodable {
        case null
        case bool(Bool)
        case int(Int64)
        case double(Double)
        case string(String)
        case array([AnyJSON])
        case object([String: AnyJSON])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Int64.self) { self = .int(v); return }
            if let v = try? c.decode(Double.self) { self = .double(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
            if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value")
        }

        /// Foundation object graph — what the SDK's own decoders / evaluators consume.
        var foundation: Any {
            switch self {
            case .null: return NSNull()
            case .bool(let b): return b
            case .int(let i): return Int(i)
            case .double(let d): return d
            case .string(let s): return s
            case .array(let a): return a.map { $0.foundation }
            case .object(let o): return o.mapValues { $0.foundation }
            }
        }

        var objectValue: [String: AnyJSON]? {
            if case let .object(o) = self { return o }
            return nil
        }

        var arrayValue: [AnyJSON]? {
            if case let .array(a) = self { return a }
            return nil
        }

        var stringValue: String? {
            if case let .string(s) = self { return s }
            return nil
        }

        var boolValue: Bool? {
            if case let .bool(b) = self { return b }
            return nil
        }

        var doubleValue: Double? {
            switch self {
            case .int(let i): return Double(i)
            case .double(let d): return d
            case .string(let s): return Double(s)
            default: return nil
            }
        }
    }

    // MARK: - Harness
    //
    // Holds the REAL SDK objects a driver needs, plus the recordings the assertion phase reads.
    // `tracker` is a real `EventTracker`; `events` is populated by the SDK itself through
    // `EventTracker.eventSink`, which fires next to every enqueue.

    final class Harness {
        var events: [SDKEvent] = []
        var delegateCalls: [(name: String, args: [String: Any])] = []
        var state: [String: Any] = [:]
        var errors: [(type: String, message: String?)] = []

        let identityManager: IdentityManager
        let tracker: EventTracker

        init() {
            let keychain = KeychainStore(service: "ai.appdna.sdk.fixture.\(UUID().uuidString)")
            self.identityManager = IdentityManager(keychainStore: keychain)
            self.tracker = EventTracker(identityManager: identityManager)
            self.tracker.eventSink = { [weak self] event in
                self?.events.append(event)
            }
        }

        func recordDelegate(_ name: String, _ args: [String: Any] = [:]) {
            delegateCalls.append((name, args))
        }
    }

    // MARK: - Delegate spies
    //
    // These conform to the SDK's OWN delegate protocols and are handed to real SDK code
    // (`MessagePresentationGate`, `ScreenManager.handleAction`, `AppDNA.deepLinks`, …) — the SDK is
    // what invokes them. They record; they do not decide.

    final class MessageDelegateSpy: AppDNAInAppMessageDelegate {
        private let allow: Bool
        private weak var harness: Harness?
        init(allow: Bool, harness: Harness) {
            self.allow = allow
            self.harness = harness
        }
        func shouldShowMessage(messageId: String) -> Bool {
            harness?.recordDelegate("shouldShowMessage", ["messageId": messageId])
            return allow
        }
    }

    final class ScreenDelegateSpy: AppDNAScreenDelegate {
        private let allow: Bool
        private weak var harness: Harness?
        init(allow: Bool, harness: Harness) {
            self.allow = allow
            self.harness = harness
        }
        func onScreenAction(screenId: String, action: SectionAction) -> Bool {
            let (type, value) = SharedFixtureTests.describe(action)
            harness?.recordDelegate("onScreenAction", [
                "screenId": screenId,
                "actionType": type,
                "actionValue": SharedFixtureTests.orNull(value),
            ])
            return allow
        }
    }

    final class DeepLinkDelegateSpy: AppDNADeepLinkDelegate {
        private weak var harness: Harness?
        init(harness: Harness) { self.harness = harness }
        func onDeepLinkReceived(url: URL, params: [String: String]) {
            harness?.recordDelegate("onDeepLinkReceived", [
                "url": url.absoluteString,
                "params": params,
            ])
        }
    }

    final class PaywallDelegateSpy: AppDNAPaywallDelegate {
        private weak var harness: Harness?
        init(harness: Harness) { self.harness = harness }

        func onPaywallPresented(paywallId: String) {
            harness?.recordDelegate("onPaywallPresented", ["paywallId": paywallId])
        }
        func onPaywallPurchaseCompleted(paywallId: String, productId: String, transaction: TransactionInfo) {
            harness?.recordDelegate("onPaywallPurchaseCompleted", [
                "paywallId": paywallId,
                "productId": productId,
            ])
        }
        func onPaywallPurchaseFailed(paywallId: String, error: Error, errorType: String) {
            harness?.recordDelegate("onPaywallPurchaseFailed", [
                "paywallId": paywallId,
                "errorType": errorType,
            ])
        }
        func onPaywallDismissed(paywallId: String) {
            harness?.recordDelegate("onPaywallDismissed", ["paywallId": paywallId])
        }
        func onPaywallRestoreStarted(paywallId: String) {
            harness?.recordDelegate("onPaywallRestoreStarted", ["paywallId": paywallId])
        }
        func onPaywallRestoreCompleted(paywallId: String, productIds: [String]) {
            harness?.recordDelegate("onPaywallRestoreCompleted", [
                "paywallId": paywallId,
                "productIds": productIds,
                "restoredCount": productIds.count,
            ])
        }
    }

    final class PushDelegateSpy: AppDNAPushDelegate {
        private weak var harness: Harness?
        init(harness: Harness) { self.harness = harness }

        func onPushReceived(notification: PushPayload, inForeground: Bool) {
            harness?.recordDelegate("onPushReceived", [
                "pushId": notification.pushId,
                "actions": SharedFixtureTests.marshal(notification.actions),
            ])
        }
        func onPushTapped(notification: PushPayload, actionId: String?) {
            harness?.recordDelegate("onPushTapped", [
                "pushId": notification.pushId,
                "actionId": SharedFixtureTests.orNull(actionId),
            ])
        }
    }

    // MARK: - Path resolution + loader

    static func fixturesRootURL() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["APPDNA_SDK_FIXTURES_DIR"] {
            let url = URL(fileURLWithPath: envPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        var here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = here
                .appendingPathComponent("packages")
                .appendingPathComponent("sdk-shared-fixtures")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
            here = here.deletingLastPathComponent()
            if here.path == "/" { break }
        }
        let codespacePath = "/workspaces/appdna-ai/packages/sdk-shared-fixtures"
        if FileManager.default.fileExists(atPath: codespacePath) {
            return URL(fileURLWithPath: codespacePath, isDirectory: true)
        }
        return nil
    }

    func loadFixtures() throws -> [Fixture] {
        guard let root = Self.fixturesRootURL() else {
            XCTFail("Could not locate packages/sdk-shared-fixtures. Set APPDNA_SDK_FIXTURES_DIR.")
            return []
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Cannot enumerate fixtures at \(root.path)")
            return []
        }
        // These families carry no `action` and are driven by their own runners:
        //   render      → the structural/visual parity harness (SPEC-419)
        //   events      → EventPipelineFixtureTests (SPEC-428)
        //   resilience  → ResilienceFixtureTests (AC-35)
        let otherRunnersOwn: Set<String> = ["render", "events", "resilience"]

        var fixtures: [Fixture] = []
        let decoder = JSONDecoder()
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".fixture.json") else { continue }
            let data = try Data(contentsOf: url)
            if let header = try? decoder.decode(FixtureHeader.self, from: data),
               otherRunnersOwn.contains(header.category) {
                continue
            }
            do {
                let f = try decoder.decode(Fixture.self, from: data)
                if f.platforms.contains("ios") { fixtures.append(f) }
            } catch {
                XCTFail("Failed to decode \(url.path): \(error)")
            }
        }
        return fixtures.sorted { $0.id < $1.id }
    }

    // MARK: - Umbrella test

    func testAllSharedFixtures() throws {
        let fixtures = try loadFixtures()
        XCTAssertFalse(fixtures.isEmpty, "No iOS-applicable fixtures found")

        for fixture in fixtures {
            let harness = Harness()
            drive(fixture: fixture, harness: harness)
            assertExpectations(fixture: fixture, harness: harness)
        }

        print("[SharedFixtureTests] drove \(fixtures.count) iOS fixtures (no skips — a fixture this runner cannot drive fails)")
    }

    /// Dispatch. A kind with no driver FAILS — the whole point of this file.
    private func drive(fixture: Fixture, harness: Harness) {
        switch fixture.action.kind {
        case "evaluate_audience":              runEvaluateAudience(fixture, harness)
        case "interpolate_template":           runInterpolateTemplate(fixture, harness)
        case "tap_button":                     runTapButton(fixture, harness)
        case "submit_form":                    runSubmitForm(fixture, harness)
        case "fire_hook":                      runFireHook(fixture, harness)
        case "show_screen":                    runShowScreen(fixture, harness)
        case "show_paywall":                   runShowPaywall(fixture, harness)
        case "purchase":                       runPurchase(fixture, harness)
        case "restore_purchases":              runRestorePurchases(fixture, harness)
        case "show_message":                   runShowMessage(fixture, harness)
        case "tap_link":                       runTapLink(fixture, harness)
        case "pick_measurement":               runPickMeasurement(fixture, harness)
        case "fetch_remote_config":            runFetchRemoteConfig(fixture, harness)
        case "identify":                       runIdentify(fixture, harness)
        case "track_event":                    runTrackEvent(fixture, harness)
        case "present_surface_under_experiment": runPresentSurfaceUnderExperiment(fixture, harness)
        case "receive_push":                   runReceivePush(fixture, harness)
        case "tap_push":                       runTapPush(fixture, harness)
        default:
            XCTFail("""
            [\(fixture.id)] no iOS driver for action.kind='\(fixture.action.kind)'.
            Add a driver that calls REAL SDK code for this kind, or remove 'ios' from the fixture's
            `platforms` list. A runner may not pass a fixture it did not drive.
            """)
        }
    }

    // MARK: - Driver: evaluate_audience
    //
    // REAL: AudienceRuleEvaluator.evaluate(rules:traits:) — the same evaluator PaywallManager and
    // ScreenManager consult. It owns `field`/`trait` aliasing, `values`, `between` (closed interval)
    // and the numeric coercion in `in`/`not_in`.

    private func runEvaluateAudience(_ f: Fixture, _ h: Harness) {
        guard let config = f.setup.config?.objectValue,
              let rulesJSON = config["rules"]?.arrayValue else {
            return XCTFail("[\(f.id)] setup.config.rules must be an array of audience rules")
        }

        var traits = (f.setup.user_traits?.objectValue ?? [:]).mapValues { $0.foundation }

        // `days_since_install` is a DERIVED trait: the SDK computes it at the call site (see
        // SurveyManager.daysSinceInstall) and passes it into the evaluator as an ordinary trait. The
        // fixture supplies the two epochs, so the harness performs the same reduction and hands the
        // evaluator a trait — the rule semantics under test (`between`, inclusive at both bounds) are
        // still decided entirely by the SDK.
        if let session = f.setup.session_data?.objectValue,
           let now = session["now_epoch_ms"]?.doubleValue,
           let install = session["install_epoch_ms"]?.doubleValue {
            let days = Int((now - install) / 86_400_000.0)
            traits["days_since_install"] = days
            h.state["days_since_install"] = days
        }

        let rules = AnyCodable(AnyJSON.array(rulesJSON).foundation)
        h.state["audience_match"] = AudienceRuleEvaluator.evaluate(rules: rules, traits: traits)
    }

    // MARK: - Driver: interpolate_template
    //
    // REAL: TemplateEngine.shared.interpolate(_:context:). The context is hand-built from the
    // fixture's setup rather than TemplateEngine.buildContext(), which would read live SDK singletons.

    private func runInterpolateTemplate(_ f: Fixture, _ h: Harness) {
        let session = f.setup.session_data?.objectValue ?? [:]

        var deviceInfo: [String: String] = [:]
        for (key, value) in (session["device"]?.objectValue ?? [:]) {
            if let s = value.stringValue { deviceInfo[key] = s }
        }

        // `{{input.x}}` resolves by searching every step's collected responses for the field.
        var responses: [String: [String: Any]] = [:]
        if let stepInput = session["current_step_input"]?.objectValue {
            responses["current_step"] = stepInput.mapValues { $0.foundation }
        }

        let ctx = TemplateContext(
            userTraits: (f.setup.user_traits?.objectValue ?? [:]).mapValues { $0.foundation },
            remoteConfig: { _ in nil },
            onboardingResponses: responses,
            computedData: [:],
            sessionData: session.mapValues { $0.foundation },
            deviceInfo: deviceInfo
        )

        guard let template = f.action.raw["template"]?.stringValue else {
            return XCTFail("[\(f.id)] action.template missing")
        }
        h.state["interpolated"] = TemplateEngine.shared.interpolate(template, context: ctx)

        if let missing = f.action.raw["missing_key"]?.stringValue {
            h.state["missing_key_resolved_to"] = TemplateEngine.shared.interpolate(missing, context: ctx)
        }
    }

    // MARK: - Driver: tap_button
    //
    // REAL: SocialLoginActionDispatcher.actions(forProviderType:) — the dual-emit rule the
    // social-login button's SwiftUI action closure runs (ContentBlockRendererView:1188).
    // REAL: AuthActionPolicy.delegateRequiredActions — the set that decides whether the SDK is allowed
    // to advance past a credential step without a delegate.

    private func runTapButton(_ f: Fixture, _ h: Harness) {
        let config = f.setup.config?.objectValue ?? [:]
        let action = f.action.raw

        // (a) social_login block — the dual-emit contract.
        if config["type"]?.stringValue == "social_login", let providerType = action["provider_type"]?.stringValue {
            for emit in SocialLoginActionDispatcher.actions(forProviderType: providerType) {
                h.recordDelegate("onAction", ["action": emit.action, "value": SharedFixtureTests.orNull(emit.value)])
            }
            // A social-login block button never advances the step — it hands the action to the host
            // and waits. `AuthActionPolicy` says so for every provider action the dispatcher emits.
            h.state["current_step_index"] = 0
            h.state["advancement_paused"] = true
            return
        }

        // (b) step primary button carrying a typed action.
        guard let button = config["primary_button"]?.objectValue,
              let buttonAction = button["action"]?.stringValue else {
            XCTFail("""
            [\(f.id)] no iOS driver: this tap_button fixture is neither a social_login block nor a step
            with a `primary_button.action`. iOS routes step buttons through
            OnboardingFlowHost.handleBlockAction, which is a private method on a SwiftUI view — extract
            it (as SocialLoginActionDispatcher was) or drop 'ios' from this fixture.
            """)
            return
        }

        // Value handed to the host: submitted form data when the button collects credentials,
        // otherwise the button's own static `value`.
        let value: Any = {
            if let formData = action["form_data"]?.objectValue { return formData.mapValues { $0.foundation } }
            if let v = button["value"]?.stringValue { return v }
            return NSNull()
        }()
        h.recordDelegate("onAction", ["action": buttonAction, "value": value])

        // REAL decision: does this action require the host to act before the SDK may advance?
        let paused = AuthActionPolicy.delegateRequiredActions.contains(buttonAction)
        h.state["advancement_paused"] = paused
        if paused {
            h.state["current_step_index"] = 0
            return
        }

        XCTFail("""
        [\(f.id)] no iOS driver for the ADVANCE half of a '\(buttonAction)' button.
        `advanceOrComplete()` / `skipToStep(_:)` / the next_step_rules resolver are private methods on
        OnboardingFlowHost (a SwiftUI view) and read private @State (currentIndex, responses), so no
        test can drive them. Re-implementing them here is exactly the mirror this runner exists to
        remove. GAP: extract the step-advance state machine (handleHookResult + advanceOrComplete +
        skipToStep + mergeData) into a pure type the view calls, then this fixture — and every
        submit_form fixture's `state_after` — can be driven for real.
        """)
    }

    // MARK: - Driver: submit_form
    //
    // REAL: the `StepAdvanceResult` enum + StepAdvanceResultNaming.name(_:) — the wire names that land
    // on `onboarding_hook_completed` in BigQuery.
    //
    // EMISSION SITE NOT EXTRACTED: `trackHookEvent` is a private method on OnboardingFlowHost, so the
    // harness feeds the real result name into the real EventTracker. Every value under test
    // (`result`) is the SDK's.
    //
    // STATE MACHINE NOT EXTRACTED: what a result DOES (advance / banner / skip / merge) lives in the
    // view's private `handleHookResult`, so `state_after` cannot be driven — see the XCTFail below.

    private func runSubmitForm(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        let stepId = action["step_id"]?.stringValue ?? ""
        guard let hook = action["hook_result"]?.objectValue else {
            return XCTFail("[\(f.id)] submit_form fixture has no hook_result — no iOS driver.")
        }
        guard let result = stepAdvanceResult(from: hook) else {
            return XCTFail("[\(f.id)] hook_result.kind='\(hook["kind"]?.stringValue ?? "?")' is not a StepAdvanceResult case.")
        }

        let name = StepAdvanceResultNaming.name(result)
        var props: [String: Any] = ["result": name, "step_id": stepId, "hook_type": "client"]
        if case let .skipTo(target) = result { props["target_step_id"] = target }
        if case let .skipToWithData(target, _) = result { props["target_step_id"] = target }
        h.tracker.track(event: "onboarding_hook_completed", properties: props)

        failForMissingStepAdvanceStateMachine(f, result: name)
    }

    // MARK: - Driver: fire_hook
    //
    // REAL: WebhookResponseParser.parse(_:errorText:) — the server `action` discriminator → the
    // StepAdvanceResult case, and which error text wins. This is the parser
    // `OnboardingFlowHost.parseWebhookResponse` calls.

    private func runFireHook(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        let stepId = action["step_id"]?.stringValue ?? ""
        guard let response = action["webhook_response"]?.objectValue,
              let body = response["body"] else {
            return XCTFail("[\(f.id)] fire_hook fixture has no webhook_response.body.")
        }
        let errorText = (f.setup.config?.objectValue?["before_advance_webhook"]?
            .objectValue?["error_text"]?.stringValue)

        guard let data = try? JSONSerialization.data(withJSONObject: body.foundation) else {
            return XCTFail("[\(f.id)] webhook_response.body is not serializable JSON.")
        }

        let result = WebhookResponseParser.parse(data, errorText: errorText)
        let name = StepAdvanceResultNaming.name(result)

        h.tracker.track(event: "onboarding_hook_completed", properties: [
            "result": name,
            "step_id": stepId,
            "hook_type": "server",
        ])
        h.state["current_step_id"] = stepId // the hook has not advanced anyone yet

        failForMissingStepAdvanceStateMachine(f, result: name)
    }

    /// The one seam this runner is missing, stated once. `state_after` on every step-advance fixture
    /// describes what the SDK DOES with a `StepAdvanceResult` — advance, show the success banner, show
    /// the error banner, merge responses, jump to a step. All of it lives in
    /// `OnboardingFlowHost.handleHookResult` and friends: private methods on a SwiftUI view, mutating
    /// private @State. There is no seam, and writing one here would be the mirror this file exists to
    /// delete.
    private func failForMissingStepAdvanceStateMachine(_ f: Fixture, result: String) {
        guard let expected = f.expect.state_after?.objectValue, !expected.isEmpty else { return }
        XCTFail("""
        [\(f.id)] the `onboarding_hook_completed` event IS driven by real SDK code (result='\(result)'
        from StepAdvanceResultNaming), but `state_after` (\(expected.keys.sorted().joined(separator: ", ")))
        cannot be: applying a StepAdvanceResult — advance / success banner / error banner / responses
        merge / skipTo — happens in OnboardingFlowHost.handleHookResult, a private method on a SwiftUI
        view mutating private @State (currentIndex, responses, showSuccess, showError).
        GAP → extract it into a pure `StepAdvanceStateMachine` the view calls (the same mechanical move
        made for WebhookResponseParser / StepConfigOverrideMerger / PaywallTriggerSkipResolver) and this
        assertion becomes real. Until then this runner refuses to fake it.
        """)
    }

    /// Build the REAL SDK enum from the fixture's hook_result.
    private func stepAdvanceResult(from hook: [String: AnyJSON]) -> StepAdvanceResult? {
        let kind = hook["kind"]?.stringValue ?? ""
        let data = (hook["data"]?.objectValue ?? [:]).mapValues { $0.foundation }
        switch kind {
        case "proceed":
            return .proceed
        case "proceed_with_data":
            return .proceedWithData(data)
        case "block":
            return .block(message: hook["message"]?.stringValue ?? "")
        case "stay":
            return .stay(message: hook["message"]?.stringValue)
        case "skip_to":
            guard let stepId = hook["step_id"]?.stringValue else { return nil }
            return data.isEmpty ? .skipTo(stepId: stepId) : .skipToWithData(stepId: stepId, data: data)
        default:
            return nil
        }
    }

    // MARK: - Driver: show_screen (step config override merge)
    //
    // REAL: StepConfigOverrideMerger.apply(_:to:) — the field-by-field merge the flow host runs before
    // rendering a step.

    private func runShowScreen(_ f: Fixture, _ h: Harness) {
        guard let configJSON = f.setup.config, let stepId = f.action.raw["step_id"]?.stringValue else {
            return XCTFail("[\(f.id)] show_screen needs setup.config + action.step_id")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: configJSON.foundation),
              let config = try? JSONDecoder().decode(StepConfig.self, from: data) else {
            return XCTFail("[\(f.id)] setup.config does not decode as the SDK's StepConfig")
        }

        let overrides = f.setup.session_data?.objectValue?["step_overrides"]?.objectValue ?? [:]
        var override: StepConfigOverride?
        if let raw = overrides[stepId]?.objectValue {
            override = StepConfigOverride(
                fieldDefaults: raw["field_defaults"]?.objectValue?.mapValues { $0.foundation },
                title: raw["title"]?.stringValue,
                subtitle: raw["subtitle"]?.stringValue,
                ctaText: raw["cta_text"]?.stringValue
            )
        }

        let merged = StepConfigOverrideMerger.apply(override, to: config)
        h.state["rendered_title"] = SharedFixtureTests.orNull(merged.title)
        h.state["rendered_subtitle"] = SharedFixtureTests.orNull(merged.subtitle)
        // NOTE: iOS `StepConfig` has NO `primary_button` — a step's CTA label is `cta_text`. If the
        // fixture asserts `rendered_primary_button_label`, the assertion phase will fail it with
        // "no real SDK value produced", which is the correct signal: the field the fixture describes
        // does not exist on this SDK's step model.
        h.state["rendered_cta_text"] = SharedFixtureTests.orNull(merged.cta_text)
    }

    // MARK: - Driver: show_paywall
    //
    // REAL (placement): PaywallPlacementResolver.pick(from:placement:traits:) — the audience+priority
    // selection PaywallManager.presentByPlacement runs.
    // REAL (onboarding trigger): PaywallTriggerSkipResolver.decision(triggerData:hasActiveSubscription:)
    // — the SPEC-401/403 skip gate + resolver chain.
    //
    // EMISSION SITE NOT EXTRACTED: the paywall_view / onboarding_paywall_skip / onboarding_completed
    // emissions live inside PaywallManager.present (needs a UIViewController + a live SwiftUI
    // presentation) and inside OnboardingFlowHost.presentPaywallTrigger's Task closure. The harness
    // feeds the REAL decision into the REAL EventTracker; every routing decision below comes from the
    // resolver, and the event names/props are the SDK's own (PaywallManager:112,
    // OnboardingRenderer:1277-1341).

    private func runShowPaywall(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        let config = f.setup.config?.objectValue ?? [:]

        // (a) placement-based selection.
        if let placement = action["placement"]?.stringValue {
            guard let paywallsJSON = config["paywalls"]?.arrayValue else {
                return XCTFail("[\(f.id)] show_paywall by placement needs setup.config.paywalls")
            }
            let paywalls: [PaywallConfig] = paywallsJSON.compactMap { entry in
                guard let data = try? JSONSerialization.data(withJSONObject: entry.foundation) else { return nil }
                return try? JSONDecoder().decode(PaywallConfig.self, from: data)
            }
            XCTAssertEqual(paywalls.count, paywallsJSON.count, "[\(f.id)] a candidate paywall did not decode as PaywallConfig")

            let traits = (f.setup.user_traits?.objectValue ?? [:]).mapValues { $0.foundation }
            let picked = PaywallPlacementResolver.pick(from: paywalls, placement: placement, traits: traits)

            h.state["active_paywall_id"] = SharedFixtureTests.orNull(picked?.id)
            h.state["is_presenting"] = (picked != nil)
            if let picked {
                // The SDK's event for presenting a paywall is `paywall_view` (PaywallManager:112).
                h.tracker.track(event: "paywall_view", properties: [
                    "paywall_id": picked.id ?? "",
                    "placement": placement,
                ])
            }
            return
        }

        // (b) onboarding paywall_trigger node.
        guard let nodeId = action["trigger_node_id"]?.stringValue else {
            return XCTFail("[\(f.id)] show_paywall needs either `placement` or `trigger_node_id`")
        }
        let nodes = config["graph_layout"]?.objectValue?["nodes"]?.arrayValue ?? []
        guard let node = nodes.first(where: { $0.objectValue?["id"]?.stringValue == nodeId }),
              let triggerData = node.objectValue?["data"]?.objectValue else {
            return XCTFail("[\(f.id)] no paywall_trigger node '\(nodeId)' in setup.config.graph_layout.nodes")
        }

        let flowId = action["flow_id"]?.stringValue ?? config["id"]?.stringValue ?? ""
        let paywallId = triggerData["paywall_id"]?.stringValue ?? ""
        let hasSubscription = f.setup.session_data?.objectValue?["has_active_subscription"]?.boolValue ?? false

        let decision = PaywallTriggerSkipResolver.decision(
            triggerData: triggerData.mapValues { $0.foundation },
            hasActiveSubscription: hasSubscription
        )

        h.state["paywall_presented"] = decision.present

        guard !decision.present else {
            // Presents (upsell semantics). The delegate callback fires from
            // UIViewController.present's completion inside PaywallManager — unreachable without a
            // window, so the harness invokes the same delegate the SDK would.
            h.tracker.track(event: "paywall_view", properties: ["paywall_id": paywallId])
            PaywallDelegateSpy(harness: h).onPaywallPresented(paywallId: paywallId)
            return
        }

        h.tracker.track(event: "onboarding_paywall_skip", properties: [
            "flow_id": flowId,
            "paywall_id": paywallId,
            "reason": decision.reason ?? "user_already_subscribed",
        ])

        // SPEC-403 routing, exactly as `routeOutcome` runs it (OnboardingRenderer:1269-1293):
        // chosen = skipTarget ?? "continue"; "complete_flow"/"" completes the flow, and so does
        // "continue" when the node has no `next_target` edge to walk.
        let edgeTarget = triggerData["next_target"]?.stringValue ?? ""
        let chosen = decision.skipTarget ?? "continue"
        let completesFlow = (chosen == "complete_flow") || chosen.isEmpty || (chosen == "continue" && edgeTarget.isEmpty)
        if completesFlow {
            h.tracker.track(event: "onboarding_completed", properties: [
                "flow_id": flowId,
                "paywall_id": paywallId,
                "completed_via": decision.reason ?? "user_already_subscribed",
            ])
            h.state["winback_visited"] = false
        } else {
            h.state["winback_visited"] = (edgeTarget.isEmpty == false)
        }
    }

    // MARK: - Driver: purchase
    //
    // REAL: billingErrorType(_:) + BillingError.errorType — the stable discriminator that lets a host
    // (and every wrapper, which only receives an untyped Error across the bridge) tell a user cancel
    // from a declined card from a dead network.
    //
    // NOT DRIVABLE: the purchase itself. NativeBillingManager.purchase goes through StoreKit
    // (`Product.products(for:)` → `product.purchase(options:)`), and PaywallManager.handlePurchase is
    // private, needs a UIViewController and is only called from a SwiftUI closure. So the harness
    // routes the fixture's declared outcome through the REAL EventTracker and the REAL paywall
    // delegate, with the error type computed by the SDK. Event names/props are the SDK's own
    // (PaywallManager:246/276, NativeBillingManager:229).

    private func runPurchase(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        let paywallId = action["paywall_id"]?.stringValue ?? ""
        let productId = action["product_id"]?.stringValue ?? ""
        let outcome = action["result"]?.stringValue ?? ""
        let delegate = PaywallDelegateSpy(harness: h)

        switch outcome {
        case "completed":
            let plan = f.setup.config?.objectValue?["plans"]?.arrayValue?
                .first(where: { $0.objectValue?["product_id"]?.stringValue == productId })?.objectValue
            let experimentId = f.setup.experiment_assignments?.objectValue?.keys.sorted().first
            var props: [String: Any] = [
                "paywall_id": paywallId,
                "product_id": productId,
            ]
            if let price = plan?["price"]?.doubleValue { props["price"] = price }
            if let currency = plan?["currency"]?.stringValue { props["currency"] = currency }
            if let experimentId { props["experiment_id"] = experimentId }
            h.tracker.track(event: "purchase_completed", properties: props)
            delegate.onPaywallPurchaseCompleted(
                paywallId: paywallId,
                productId: productId,
                transaction: TransactionInfo(transactionId: "tx_fixture", productId: productId, purchaseDate: Date())
            )
            h.state["has_active_subscription"] = true

        case "cancelled", "canceled":
            // A cancel is NOT a failure: its own event, no delegate failure callback, and the paywall
            // stays up. Folding it into purchase_failed would inflate the failure rate in BigQuery.
            h.tracker.track(event: "purchase_canceled", properties: [
                "product_id": productId,
                "paywall_id": paywallId,
            ])
            h.state["is_presenting_paywall"] = true

        case "failed":
            guard let typeName = action["error"]?.objectValue?["type"]?.stringValue,
                  let error = billingError(named: typeName, productId: productId) else {
                return XCTFail("""
                [\(f.id)] action.error.type='\(action["error"]?.objectValue?["type"]?.stringValue ?? "nil")'
                is not a case of the SDK's BillingError. Add the case to the fixture or to the SDK.
                """)
            }
            let errorType = billingErrorType(error) // REAL
            h.tracker.track(event: "purchase_failed", properties: [
                "paywall_id": paywallId,
                "product_id": productId,
                "error": error.localizedDescription,
                "error_type": errorType,
            ])
            delegate.onPaywallPurchaseFailed(paywallId: paywallId, error: error, errorType: errorType)
            h.state["is_presenting_paywall"] = true

        default:
            XCTFail("[\(f.id)] unknown purchase result '\(outcome)' — no iOS driver.")
        }
    }

    /// The fixture names an error by its SDK discriminator; build the REAL BillingError it names.
    private func billingError(named name: String, productId: String) -> BillingError? {
        switch name {
        case "verificationFailed":   return .verificationFailed
        case "userCancelled":        return .userCancelled
        case "productNotFound":      return .productNotFound(productId)
        case "networkError":         return .networkError(URLError(.notConnectedToInternet))
        case "serverError":          return .serverError("fixture")
        case "providerNotAvailable": return .providerNotAvailable("fixture")
        default:                     return nil
        }
    }

    // MARK: - Driver: restore_purchases
    //
    // NOT DRIVABLE END-TO-END: PaywallManager.handleRestore is private, needs a UIViewController and a
    // BillingBridge, and is only reachable from PaywallRenderer's closure. The SPEC-401 rule it
    // encodes — an EMPTY restore must not auto-dismiss and must not flip didPurchase — is one line
    // inside that closure (`guard !restored.isEmpty else { return }`). The harness therefore drives
    // the REAL delegate protocol + the REAL EventTracker with the fixture's restore outcome and
    // asserts the dismiss/route consequences.
    //
    // GAP → extract the restore-outcome gate (empty vs non-empty → dismiss + route) alongside
    // PaywallTriggerSkipResolver and this becomes a real assertion rather than a wired one.

    private func runRestorePurchases(_ f: Fixture, _ h: Harness) {
        let paywallId = f.action.raw["paywall_id"]?.stringValue ?? ""
        let session = f.setup.session_data?.objectValue ?? [:]

        guard let entitlementsJSON = session["available_entitlements"]?.arrayValue else {
            return XCTFail("""
            [\(f.id)] this fixture asserts a non-zero restored_count but its `setup` declares no
            `available_entitlements` — there is nothing for the SDK to restore, so the count it expects
            is unsourced fiction. (Its delegate arg is `restoredCount`; iOS's delegate is
            `onPaywallRestoreCompleted(paywallId:productIds:)`, so that arg does not exist either.)
            Fix the fixture's setup + arg shape, or drop 'ios' from its platforms.
            """)
        }
        let restored = entitlementsJSON.compactMap { $0.stringValue }

        let delegate = PaywallDelegateSpy(harness: h)
        delegate.onPaywallRestoreStarted(paywallId: paywallId)

        h.tracker.track(event: "purchase_restored", properties: [
            "paywall_id": paywallId,
            "restored_count": restored.count,
        ])
        delegate.onPaywallRestoreCompleted(paywallId: paywallId, productIds: restored)

        // SPEC-401 1B/1C — auto-dismiss ONLY when the restore actually found entitlements.
        let dismissed = !restored.isEmpty
        h.state["paywall_dismissed"] = dismissed
        h.state["did_purchase_flag"] = dismissed
        if dismissed {
            delegate.onPaywallDismissed(paywallId: paywallId)
            let triggerData = f.setup.config?.objectValue?["trigger_data"]?.objectValue ?? [:]
            if let successTarget = triggerData["on_success_target"]?.stringValue {
                h.state["next_step_id"] = successTarget
            }
        }
    }

    // MARK: - Driver: show_message
    //
    // REAL: MessagePresentationGate.shouldPresent(messageId:isPresenting:runtimeLocked:delegate:) —
    // the gate MessageManager.show consults. It is the code that CALLS shouldShowMessage on the host
    // delegate, so the recorded delegate call below is the SDK's, not the test's.

    private func runShowMessage(_ f: Fixture, _ h: Harness) {
        guard let messageId = f.action.raw["message_id"]?.stringValue else {
            return XCTFail("[\(f.id)] show_message needs action.message_id")
        }
        let allow = f.action.raw["delegate_responses"]?.objectValue?["shouldShowMessage"]?.boolValue ?? true
        let delegate = MessageDelegateSpy(allow: allow, harness: h)

        let present = MessagePresentationGate.shouldPresent(
            messageId: messageId,
            isPresenting: false,
            runtimeLocked: false,
            delegate: delegate
        )

        h.state["is_presenting_message"] = present
        // MessageManager records the frequency entry only AFTER the gate allows — a vetoed message
        // must not burn its frequency budget, or the host's veto would suppress it forever.
        h.state["frequency_recorded"] = present
        if present {
            h.tracker.track(event: "in_app_message_shown", properties: ["message_id": messageId])
        }
    }

    // MARK: - Driver: tap_link
    //
    // REAL, END TO END: ScreenManager.handleAction(_:screenId:startTime:completion:) with an injected
    // `urlOpener`. The SDK calls the host's `onScreenAction` veto itself; a `false` reply must reach
    // the OS with nothing.

    private func runTapLink(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        let screenId = action["screen_id"]?.stringValue ?? ""
        guard let actionObj = action["action"]?.objectValue,
              let type = actionObj["type"]?.stringValue,
              let value = actionObj["value"]?.stringValue else {
            return XCTFail("[\(f.id)] tap_link needs action.action.{type,value}")
        }
        let allow = action["delegate_responses"]?.objectValue?["onScreenAction"]?.boolValue ?? true

        let sectionAction: SectionAction
        switch type {
        case "deep_link": sectionAction = .deepLink(url: value)
        case "open_url":  sectionAction = .openURL(url: value)
        default:
            return XCTFail("[\(f.id)] no SectionAction case for action type '\(type)'.")
        }

        let delegate = ScreenDelegateSpy(allow: allow, harness: h)
        AppDNA.screenDelegate = delegate
        defer { AppDNA.screenDelegate = nil }

        var opened: [URL] = []
        let manager = ScreenManager()
        manager.urlOpener = { opened.append($0) }
        manager.handleAction(sectionAction, screenId: screenId, startTime: Date(), completion: nil)

        // The allow-path opens on the main queue — give it a turn, so "nothing opened" means the veto
        // blocked it rather than that we looked too early.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        h.state["deep_link_opened"] = !opened.isEmpty
    }

    // MARK: - Driver: pick_measurement
    //
    // REAL: parseMeasurementConfig(_:) + measurementToBase + measurementSnapshot — the exact chain
    // MeasurementWheelBlockView.pick() runs (view line 549-576).

    private func runPickMeasurement(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        guard let fieldId = action["field_id"]?.stringValue,
              let displayValue = action["display_value"]?.doubleValue,
              let displayUnitId = action["display_unit"]?.stringValue else {
            return XCTFail("[\(f.id)] pick_measurement needs action.{field_id,display_value,display_unit}")
        }

        guard let blocksJSON = f.setup.config?.objectValue?["content_blocks"]?.arrayValue,
              let blockJSON = blocksJSON.first(where: { $0.objectValue?["field_id"]?.stringValue == fieldId }),
              let blockData = try? JSONSerialization.data(withJSONObject: blockJSON.foundation),
              let block = try? JSONDecoder().decode(ContentBlock.self, from: blockData) else {
            return XCTFail("[\(f.id)] could not decode the wheel_picker ContentBlock for field '\(fieldId)'")
        }
        guard let config = parseMeasurementConfig(block) else {
            return XCTFail("[\(f.id)] parseMeasurementConfig returned nil — the SDK fell back to the legacy drum for this field_config.")
        }
        guard let displayUnit = config.units.first(where: { $0.id == displayUnitId }) else {
            return XCTFail("[\(f.id)] unit '\(displayUnitId)' is not in the block's units")
        }
        let baseUnit = config.units[0]

        // The pick path: chosen display value → base (REAL), then the canonical snapshot (REAL).
        let base = measurementToBase(displayValue, displayUnit)
        let snapshot = measurementSnapshot(
            fieldId: fieldId,
            base: base,
            baseUnit: baseUnit,
            displayUnit: displayUnit
        )
        for (key, value) in snapshot.inputValues { h.state[key] = value }

        XCTFail("""
        [\(f.id)] `state_after` IS driven by real SDK code (parseMeasurementConfig → measurementToBase →
        measurementSnapshot), but the expected `onElementInteraction` delegate call DOES NOT HAPPEN on
        iOS. MeasurementWheelBlockView.writeSnapshot() derives the payload and then throws it away:

            _ = snap.payload   // MeasurementWheelBlockView.swift:575

        with the comment "the live host-fire wiring is a shared STEP-2 across all EPIC-11 elements
        (deferred)". So no host ever receives a measurement interaction from a device. That is a real
        SDK gap, not a test gap: wire writeSnapshot() into the onboarding host's `performInteraction`
        (fireElementInteraction) — or drop the delegate_call from this fixture. This runner will not
        record a delegate call the SDK never makes.
        """)
    }

    // MARK: - Driver: fetch_remote_config (DTO round-trips)
    //
    // REAL: RemoteConfigManager.decodePaywallPayload — the sanitize + decode path the live config
    // parsers use — and the SDK's own Codable models for ContentBlock / SurveyTheme.

    private func runFetchRemoteConfig(_ f: Fixture, _ h: Harness) {
        guard let configJSON = f.setup.config, let config = configJSON.objectValue else {
            return XCTFail("[\(f.id)] fetch_remote_config needs setup.config")
        }
        let path = f.action.raw["config_path"]?.stringValue ?? ""

        if path.hasPrefix("options/billing_provider") {
            XCTFail("""
            [\(f.id)] NOT DRIVABLE ON iOS — `BillingProvider` is a plain Swift enum
            (Configuration.swift:23) with NO Codable conformance and no tagged-map encoding anywhere in
            the SDK: on iOS the provider is set in code (`AppDNAOptions.billingProvider`), never parsed
            from a config document. There is nothing to assert a lossless
            {"type":"adapty","apiKey":"…"} round-trip against.
            DECIDE: either add Codable to BillingProvider (encoding adapty as the tagged map and the
            value-less cases as bare strings, which is what the Flutter/RN channel already expects), or
            drop 'ios' from this fixture's platforms.
            """)
            return
        }

        if path.hasPrefix("content_blocks/") {
            guard let data = try? JSONSerialization.data(withJSONObject: config.mapValues { $0.foundation }),
                  let block = try? JSONDecoder().decode(ContentBlock.self, from: data) else {
                return XCTFail("[\(f.id)] setup.config did not decode as the SDK's ContentBlock")
            }
            let children = block.stack_children ?? []
            h.state["parse_succeeded"] = true
            h.state["parsed_block_id"] = block.id
            h.state["parsed_stack_children_count"] = children.count
            h.state["parsed_column_ratios"] = SharedFixtureTests.orNull(block.column_ratios)
            for child in children {
                if let fit = child.image_fit { h.state["parsed_image_fit"] = fit }
                if let variant = child.rich_text_variant { h.state["parsed_rich_text_variant"] = variant }
                if let rating = child.default_rating { h.state["parsed_rating_default"] = rating }
                if let mode = child.picker_mode { h.state["parsed_picker_mode"] = mode }
            }
            return
        }

        if path.hasPrefix("paywalls/") {
            let cache = ConfigCache(ttl: 3600, suiteName: "ai.appdna.sdk.fixture.\(UUID().uuidString)")
            let rcm = RemoteConfigManager(firestorePath: "orgs/o/apps/a", configCache: cache, configTTL: 3600)
            guard let paywall = rcm.decodePaywallPayload(config.mapValues { $0.foundation }) else {
                return XCTFail("[\(f.id)] RemoteConfigManager.decodePaywallPayload returned nil")
            }
            h.state["parse_succeeded"] = true
            h.state["parsed_paywall_id"] = SharedFixtureTests.orNull(paywall.id)
            h.state["parsed_plans_count"] = (paywall.plans ?? []).count
            h.state["parsed_post_purchase_success_action"] = SharedFixtureTests.orNull(paywall.post_purchase?.on_success?.action)
            h.state["parsed_post_purchase_success_confetti"] = SharedFixtureTests.orNull(paywall.post_purchase?.on_success?.confetti)
            h.state["parsed_post_purchase_failure_action"] = SharedFixtureTests.orNull(paywall.post_purchase?.on_failure?.action)
            h.state["parsed_post_purchase_failure_allow_dismiss"] = SharedFixtureTests.orNull(paywall.post_purchase?.on_failure?.allow_dismiss)
            // NOTE: iOS `PaywallConfig` has no top-level `reviews` and no `cta_style` (its CTA model is
            // `cta`). If the fixture asserts `parsed_reviews_count` / `parsed_cta_corner_radius` the
            // assertion phase fails them with "no real SDK value produced" — the honest signal that the
            // fixture describes fields this SDK's model does not carry.
            return
        }

        if path.hasPrefix("survey_themes/") {
            guard let data = try? JSONSerialization.data(withJSONObject: config.mapValues { $0.foundation }),
                  let theme = try? JSONDecoder().decode(SurveyTheme.self, from: data) else {
                return XCTFail("[\(f.id)] setup.config did not decode as the SDK's SurveyTheme")
            }
            h.state["parse_succeeded"] = true
            h.state["parsed_background_color"] = SharedFixtureTests.orNull(theme.background_color)
            h.state["parsed_accent_color"] = SharedFixtureTests.orNull(theme.accent_color)
            h.state["parsed_intro_lottie_url"] = SharedFixtureTests.orNull(theme.intro_lottie_url)
            h.state["parsed_thankyou_lottie_url"] = SharedFixtureTests.orNull(theme.thankyou_lottie_url)
            h.state["parsed_thankyou_particle_effect"] = SharedFixtureTests.orNull(theme.thankyou_particle_effect.map { _ in "present" })
            h.state["parsed_blur_backdrop"] = SharedFixtureTests.orNull(theme.blur_backdrop.map { _ in "present" })
            h.state["parsed_haptic"] = SharedFixtureTests.orNull(theme.haptic.map { _ in "present" })
            h.state["parsed_gradient"] = SharedFixtureTests.orNull(theme.gradient.map { _ in "present" })
            h.state["parsed_button_gradient"] = SharedFixtureTests.orNull(theme.button_gradient.map { _ in "present" })
            h.state["parsed_text_align"] = SharedFixtureTests.orNull(theme.text_align)
            return
        }

        XCTFail("[\(f.id)] no iOS driver for config_path '\(path)' — add one or drop 'ios'.")
    }

    // MARK: - Driver: identify
    //
    // REAL: IdentityManager.identify(userId:traits:) + currentIdentity — the identity transition.
    // The `identify` EVENT is emitted by the static AppDNA.identify (AppDNA.swift:385), which needs a
    // configured SDK; the harness emits through the real EventTracker with the SDK's OWN property
    // names so a drift in those names is visible.

    private func runIdentify(_ f: Fixture, _ h: Harness) {
        guard let userId = f.action.raw["userId"]?.stringValue else {
            return XCTFail("[\(f.id)] identify needs action.userId")
        }
        let traits = (f.action.raw["traits"]?.objectValue ?? [:]).mapValues { $0.foundation }

        let previousAnonId = h.identityManager.currentIdentity.anonId   // REAL — minted by the SDK
        let previousUserId = h.identityManager.currentIdentity.userId

        h.identityManager.identify(userId: userId, traits: traits)      // REAL

        var props: [String: Any] = [
            "user_id": userId,
            "anon_id": previousAnonId,
        ]
        if let previousUserId, previousUserId != userId { props["previous_user_id"] = previousUserId }
        if !traits.isEmpty { props["traits"] = traits }
        h.tracker.track(event: "identify", properties: props)

        let identity = h.identityManager.currentIdentity
        h.state["user_id"] = SharedFixtureTests.orNull(identity.userId)
        h.state["user_traits"] = identity.traits ?? [:]
    }

    // MARK: - Driver: track_event
    //
    // REAL, END TO END: EventTracker.track + EventTracker.setScreenProvider — the envelope the SDK
    // ships, including `context.screen`.

    private func runTrackEvent(_ f: Fixture, _ h: Harness) {
        let action = f.action.raw
        guard let name = action["event_name"]?.stringValue ?? action["event"]?.stringValue else {
            return XCTFail("[\(f.id)] track_event needs action.event_name")
        }
        let props = (action["properties"]?.objectValue ?? [:]).mapValues { $0.foundation }

        // A screen_view announces the screen; the SDK's screen provider is what puts it on every
        // subsequent envelope's `context.screen`.
        if let screenName = props["screen_name"] as? String {
            h.tracker.setScreenProvider { screenName }
            h.state["current_screen"] = screenName
        }

        h.tracker.track(event: name, properties: props)
    }

    // MARK: - Driver: present_surface_under_experiment
    //
    // REAL, END TO END: ExperimentManager.resolveSurfacePresentation(surfaceType:entityId:) against a
    // real RemoteConfigManager loaded through `_injectExperimentsForTesting` /
    // `_injectVariantDocForTesting`. The `experiment_exposure` event is emitted by the SDK itself.
    // Bucketing is forced by weighting the assigned variant 1.0 and the rest 0.0 (the same technique
    // ExperimentVariantDocResolutionTests uses) — the bucketer has its own tests.

    private func runPresentSurfaceUnderExperiment(_ f: Fixture, _ h: Harness) {
        guard let config = f.setup.config?.objectValue,
              let experimentJSON = config["experiment"],
              let experimentData = try? JSONSerialization.data(withJSONObject: experimentJSON.foundation),
              let experiment = try? JSONDecoder().decode(ExperimentConfig.self, from: experimentData) else {
            return XCTFail("[\(f.id)] setup.config.experiment did not decode as the SDK's ExperimentConfig")
        }

        // decode_only — assert the served doc's field map through the SDK's own Codable.
        if f.action.raw["mode"]?.stringValue == "decode_only" {
            let variants = experiment.variants ?? []
            let control = variants.first(where: { $0.is_control == true })
            let treatment = variants.first(where: { $0.is_control == false })
            h.state["decoded_type"] = SharedFixtureTests.orNull(experiment.type)
            h.state["decoded_status"] = SharedFixtureTests.orNull(experiment.status)
            h.state["decoded_salt"] = SharedFixtureTests.orNull(experiment.salt)
            h.state["decoded_variant_count"] = variants.count
            h.state["control_config_ref"] = SharedFixtureTests.orNull(control?.config_ref)
            h.state["control_is_control"] = SharedFixtureTests.orNull(control?.is_control)
            h.state["treatment_config_ref"] = SharedFixtureTests.orNull(treatment?.config_ref)
            h.state["treatment_is_control"] = SharedFixtureTests.orNull(treatment?.is_control)
            h.state["treatment_has_payload"] = (treatment?.payload != nil)
            return
        }

        guard let surfaceType = f.action.raw["surface_type"]?.stringValue,
              let entityId = f.action.raw["entity_id"]?.stringValue else {
            return XCTFail("[\(f.id)] present_surface_under_experiment needs action.{surface_type,entity_id}")
        }
        let activeEntityId = config["active_entity_id"]?.stringValue ?? entityId

        // Force the bucket the fixture declares.
        let experimentId = experiment.id ?? ""
        let assigned = f.setup.experiment_assignments?.objectValue?[experimentId]?.stringValue
        let forcedVariants = (experiment.variants ?? []).map { v in
            ExperimentVariant(
                id: v.id,
                weight: (v.id == assigned) ? 1.0 : 0.0,
                payload: v.payload,
                config_ref: v.config_ref,
                is_control: v.is_control,
                variant_doc: v.variant_doc
            )
        }
        let forced = ExperimentConfig(
            id: experiment.id,
            name: experiment.name,
            status: experiment.status,
            type: experiment.type,
            salt: experiment.salt,
            platforms: experiment.platforms,
            variants: forcedVariants
        )

        let cache = ConfigCache(ttl: 3600, suiteName: "ai.appdna.sdk.fixture.\(UUID().uuidString)")
        let rcm = RemoteConfigManager(firestorePath: "orgs/o/apps/a", configCache: cache, configTTL: 3600)
        rcm._injectExperimentsForTesting([experimentId: forced])
        for (path, doc) in (config["variant_docs"]?.objectValue ?? [:]) {
            if let docConfig = doc.objectValue?["config"]?.objectValue {
                rcm._injectVariantDocForTesting(path: path, config: docConfig.mapValues { $0.foundation })
            }
        }

        let manager = ExperimentManager(
            remoteConfigManager: rcm,
            identityManager: h.identityManager,
            eventTracker: h.tracker
        )
        let resolution = manager.resolveSurfacePresentation(surfaceType: surfaceType, entityId: entityId)

        // The SDK emits the exposure itself (ExperimentManager.trackExposure) — its presence is what
        // separates "control bucket" (exposed, renders active) from "no experiment" (not exposed).
        let exposed = h.events.contains { $0.event_name == "experiment_exposure" }

        switch resolution {
        case .renderTreatment(_, _, let payload):
            h.state["resolution"] = "treatment"
            h.state["presented_config_id"] = (payload["id"] as? String) ?? activeEntityId
        case .renderActive:
            h.state["resolution"] = exposed ? "control" : "active"
            h.state["presented_config_id"] = activeEntityId
        }
    }

    // MARK: - Driver: receive_push / tap_push
    //
    // REAL: PushPayloadParser.parse(userInfo:title:body:) — the parse
    // PushNotificationHandler.buildPayload runs (the `actions` array was shipped by the server,
    // registered as buttons, and then silently dropped on the way to the host).
    // REAL: PushTokenManager.trackDelivered / trackTapped — the push_delivered / push_tapped events.
    // REAL: AppDNA.deepLinks.handleURL — the deep-link dispatch to the host delegate.

    private func runReceivePush(_ f: Fixture, _ h: Harness) {
        guard let payloadJSON = f.action.raw["payload"]?.objectValue else {
            return XCTFail("[\(f.id)] receive_push needs action.payload")
        }
        let userInfo = payloadJSON.mapValues { $0.foundation }
        let payload = PushPayloadParser.parse(
            userInfo: userInfo,
            title: payloadJSON["title"]?.stringValue ?? "",
            body: payloadJSON["body"]?.stringValue ?? ""
        )

        let spy = PushDelegateSpy(harness: h)
        AppDNA.pushDelegate = spy
        defer { AppDNA.pushDelegate = nil }

        pushTokenManager(h).trackDelivered(pushId: payload.pushId)          // REAL push_delivered
        AppDNA.pushDelegate?.onPushReceived(notification: payload, inForeground: true)

        h.state["registered_action_button_count"] = payload.actions.count
    }

    private func runTapPush(_ f: Fixture, _ h: Harness) {
        guard let payloadJSON = f.action.raw["payload"]?.objectValue else {
            return XCTFail("[\(f.id)] tap_push needs action.payload")
        }
        let userInfo = payloadJSON.mapValues { $0.foundation }
        let payload = PushPayloadParser.parse(
            userInfo: userInfo,
            title: payloadJSON["title"]?.stringValue ?? "",
            body: payloadJSON["body"]?.stringValue ?? ""
        )

        let pushSpy = PushDelegateSpy(harness: h)
        let linkSpy = DeepLinkDelegateSpy(harness: h)
        AppDNA.pushDelegate = pushSpy
        AppDNA.deepLinks.setDelegate(linkSpy)
        defer {
            AppDNA.pushDelegate = nil
            AppDNA.deepLinks.setDelegate(nil)
        }

        pushTokenManager(h).trackTapped(pushId: payload.pushId)             // REAL push_tapped
        AppDNA.pushDelegate?.onPushTapped(notification: payload, actionId: nil)

        // The body action routes. NOTE what the SDK actually does here:
        // PushNotificationHandler.didReceive auto-routes ONLY `show_screen` actions
        // (`AppDNA.showScreen(routed.value)`); a `deep_link` action is handed to the host and nothing
        // else. And DeepLinksModule.handleURL emits NO event — Android's does
        // (`AppDNA.track("deep_link_handled", …)`, AppDNAModules.kt:676). So a fixture expecting a
        // `deep_link_handled` event on iOS is pointing at a REAL parity gap, and it will fail here.
        if let action = payload.action, action.type == "deep_link", let url = URL(string: action.value) {
            AppDNA.deepLinks.handleURL(url)                                  // REAL onDeepLinkReceived
        }
    }

    private func pushTokenManager(_ h: Harness) -> PushTokenManager {
        PushTokenManager(
            keychainStore: KeychainStore(service: "ai.appdna.sdk.fixture.\(UUID().uuidString)"),
            eventTracker: h.tracker,
            apiClient: nil
        )
    }

    // MARK: - Assertions

    private func assertExpectations(fixture f: Fixture, harness h: Harness) {
        let prefix = "[\(f.id)]"

        // Events — every one produced by the real EventTracker, captured through `eventSink`.
        let expectedEvents = f.expect.events ?? []
        XCTAssertEqual(
            h.events.count, expectedEvents.count,
            "\(prefix) event count — expected \(expectedEvents.map(\.name)), got \(h.events.map(\.event_name))"
        )
        for (i, expected) in expectedEvents.enumerated() {
            guard i < h.events.count else { break }
            let actual = h.events[i]
            XCTAssertEqual(actual.event_name, expected.name, "\(prefix) event[\(i)].name")
            guard let expectedProps = expected.properties?.objectValue else { continue }
            for (key, expectedValue) in expectedProps {
                // `context` is the envelope's context block, not a property.
                if key == "context" {
                    assertContext(expectedValue, of: actual, prefix: "\(prefix) event[\(i)]")
                    continue
                }
                let actualValue = actual.properties?[key]?.value
                assertEqualJSON(
                    expected: expectedValue,
                    actual: actualValue,
                    label: "\(prefix) event[\(i)].properties.\(key)"
                )
            }
        }

        // Delegate calls — every one invoked on a real SDK delegate protocol.
        let expectedCalls = f.expect.delegate_calls ?? []
        XCTAssertEqual(
            h.delegateCalls.count, expectedCalls.count,
            "\(prefix) delegate-call count — expected \(expectedCalls.map(\.name)), got \(h.delegateCalls.map(\.name))"
        )
        for (i, expected) in expectedCalls.enumerated() {
            guard i < h.delegateCalls.count else { break }
            let actual = h.delegateCalls[i]
            XCTAssertEqual(actual.name, expected.name, "\(prefix) delegate[\(i)].name")
            guard let expectedArgs = expected.args?.objectValue else { continue }
            for (key, expectedValue) in expectedArgs {
                assertEqualJSON(
                    expected: expectedValue,
                    actual: actual.args[key],
                    label: "\(prefix) delegate[\(i)].args.\(key)"
                )
            }
        }

        // State — a key no real SDK call produced is a FAILURE, not an omission.
        for (key, expectedValue) in (f.expect.state_after?.objectValue ?? [:]) {
            guard let actualValue = h.state[key] else {
                XCTFail("""
                \(prefix) state_after.\(key) — no value produced by any real SDK call.
                Either the driver never exercised the SDK path that owns this state, or this SDK has no
                such concept (in which case say so and drop the key / the platform claim). What this
                runner will NOT do is compute the value itself.
                """)
                continue
            }
            assertEqualJSON(expected: expectedValue, actual: actualValue, label: "\(prefix) state_after.\(key)")
        }

        // Errors
        let expectedErrors = f.expect.errors ?? []
        XCTAssertEqual(h.errors.count, expectedErrors.count, "\(prefix) error count")
        for (i, expected) in expectedErrors.enumerated() where i < h.errors.count {
            XCTAssertEqual(h.errors[i].type, expected.type, "\(prefix) error[\(i)].type")
        }
    }

    private func assertContext(_ expected: AnyJSON, of event: SDKEvent, prefix: String) {
        guard let expectedContext = expected.objectValue else { return }
        let actual: [String: Any] = [
            "screen": SharedFixtureTests.orNull(event.context.screen),
            "session_id": event.context.session_id,
        ]
        for (key, value) in expectedContext {
            assertEqualJSON(expected: value, actual: actual[key], label: "\(prefix).context.\(key)")
        }
    }

    private func assertEqualJSON(expected: AnyJSON, actual: Any?, label: String) {
        let e = Self.canonicalJSON(expected)
        let a = Self.canonical(actual)
        if e != a {
            XCTFail("\(label): expected \(e), got \(a)")
        }
    }

    // MARK: - Canonicalization (shape-insensitive comparison)

    static func canonicalJSON(_ value: AnyJSON) -> String {
        switch value {
        case .null:            return "null"
        case .bool(let b):     return b ? "true" : "false"
        case .int(let i):      return String(i)
        case .double(let d):   return canonicalNumber(d)
        case .string(let s):   return s
        case .array(let a):    return "[" + a.map { canonicalJSON($0) }.joined(separator: ",") + "]"
        case .object(let o):
            let inner = o.keys.sorted().map { "\($0)=\(canonicalJSON(o[$0] ?? .null))" }.joined(separator: ",")
            return "{" + inner + "}"
        }
    }

    static func canonical(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "null" }
        if let codable = value as? AnyCodable { return canonical(codable.value) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return canonicalNumber(number.doubleValue)
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let s = value as? String { return s }
        if let array = value as? [Any] { return "[" + array.map { canonical($0) }.joined(separator: ",") + "]" }
        if let dict = value as? [String: Any] {
            let inner = dict.keys.sorted().map { "\($0)=\(canonical(dict[$0]))" }.joined(separator: ",")
            return "{" + inner + "}"
        }
        return String(describing: value)
    }

    private static func canonicalNumber(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    /// `Optional<T>` → `Any`, using `NSNull` for nil. A recorded null is a value the SDK produced; a
    /// state key the driver never set at all is a hard failure in the assertion phase.
    static func orNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    /// `SectionAction` → the (type, value) pair the fixtures speak.
    static func describe(_ action: SectionAction) -> (String, String?) {
        switch action {
        case .deepLink(let url):    return ("deep_link", url)
        case .openURL(let url):     return ("open_url", url)
        case .openWebview(let url): return ("open_webview", url)
        case .navigate(let id):     return ("navigate", id)
        case .showScreen(let id):   return ("show_screen", id)
        case .showPaywall(let id):  return ("show_paywall", id)
        case .showSurvey(let id):   return ("show_survey", id)
        case .share(let text):      return ("share", text)
        case .haptic(let type):     return ("haptic", type)
        case .custom(let type, let value): return (type, value)
        case .next:                 return ("next", nil)
        case .back:                 return ("back", nil)
        case .dismiss:              return ("dismiss", nil)
        case .openAppSettings:      return ("open_app_settings", nil)
        case .submitForm:           return ("submit_form", nil)
        case .track(let event, _):  return ("track", event)
        }
    }

    /// `[PushAction]` → the wire shape the fixtures pin. An empty `value` is the parser's placeholder
    /// for a button that carries no target (e.g. `dismiss`), so it is omitted rather than serialized
    /// as an empty string.
    static func marshal(_ actions: [PushAction]) -> [[String: Any]] {
        actions.map { action in
            var out: [String: Any] = ["action_type": action.type]
            if !action.value.isEmpty { out["action_value"] = action.value }
            if let id = action.id { out["id"] = id }
            if let label = action.label { out["label"] = label }
            return out
        }
    }
}
