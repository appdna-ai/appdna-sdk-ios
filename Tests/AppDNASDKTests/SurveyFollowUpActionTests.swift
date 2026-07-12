import XCTest
@testable import AppDNASDK

/// 🔴 SURVEY FOLLOW-UP ACTIONS WERE HALF-IMPLEMENTED ON iOS.
///
/// `executeFollowUpAction` fired `.positive` ONLY when the action was `prompt_review`, `.negative`
/// ONLY when it was `show_feedback_form`, and `.neutral` was a bare `break` — `actions.on_neutral`,
/// declared at SurveyConfig.swift:265 and authorable in the console, was never read by a single line
/// of iOS code. `trigger_winback` — which the console offers as a first-class choice for detractors
/// (`feedback-loop/entities/Survey.ts:107`) — did LITERALLY NOTHING on iOS while Android fired it.
/// And iOS emitted no follow-up analytics at all, so the entire `survey_followup_*` funnel was an
/// Android-only dataset and the two platforms' feedback loops were not comparable.
///
/// Android's implementation (`feedback/SurveyManager.kt:299-343`) is the reference: sentiment
/// (INCLUDING neutral) selects the action; the action string routes to prompt_review /
/// show_feedback_form / trigger_winback / dismiss; each emits `survey_followup_*` with `survey_id` +
/// `sentiment` (+ `message` for winback).
///
/// Falsification: restore the old `switch sentiment { case .positive: if …== "prompt_review" … }`
/// body and every test below goes RED — no event is emitted on any path.
final class SurveyFollowUpActionTests: XCTestCase {

    /// A SurveyManager whose emitted envelopes are readable. `eventSink` is the tracker's test seam.
    private func makeManager() -> (SurveyManager, () -> [(String, [String: Any])]) {
        let cache = ConfigCache(ttl: 3600, suiteName: "ai.appdna.sdk.test.\(UUID().uuidString)")
        let rcm = RemoteConfigManager(firestorePath: "orgs/o/apps/a", configCache: cache, configTTL: 3600)
        let keychain = KeychainStore(service: "ai.appdna.sdk.test.\(UUID().uuidString)")
        let identity = IdentityManager(keychainStore: keychain)
        let tracker = EventTracker(identityManager: identity)

        var captured: [(String, [String: Any])] = []
        tracker.eventSink = { event in
            let props = (event.properties ?? [:]).mapValues { $0.value }
            captured.append((event.event_name, props))
        }
        let manager = SurveyManager(remoteConfigManager: rcm, eventTracker: tracker)
        return (manager, { captured })
    }

    /// An NPS survey whose three sentiment buckets each carry a follow-up action.
    private func config(
        onPositive: String? = nil,
        onNegative: String? = nil,
        onNeutral: String? = nil,
        message: String? = nil
    ) throws -> SurveyConfig {
        func action(_ a: String?) -> String {
            guard let a else { return "null" }
            let msg = message.map { "\"\($0)\"" } ?? "null"
            return "{ \"action\": \"\(a)\", \"message\": \(msg) }"
        }
        let json = """
        {
            "name": "NPS",
            "survey_type": "nps",
            "questions": [{ "id": "q1", "type": "nps", "text": "?" }],
            "follow_up_actions": {
                "on_positive": \(action(onPositive)),
                "on_negative": \(action(onNegative)),
                "on_neutral": \(action(onNeutral))
            }
        }
        """
        return try JSONDecoder().decode(SurveyConfig.self, from: Data(json.utf8))
    }

    // NPS scoring (SurveyManager.determineSentiment): >=9 positive, <=6 negative, 7-8 neutral.
    private func answer(_ score: Int) -> [SurveyAnswer] {
        [SurveyAnswer(question_id: "q1", answer: score)]
    }

    // MARK: - The reported bug

    /// "Detractor → trigger_winback" fired on Android and did LITERALLY NOTHING on iOS.
    func testDetractorTriggerWinbackFires() throws {
        let (manager, events) = makeManager()
        let cfg = try config(onNegative: "trigger_winback", message: "Come back — 50% off")

        manager.executeFollowUpAction(surveyId: "srv_1", config: cfg, answers: answer(2))

        let winback = events().filter { $0.0 == "survey_followup_winback" }
        XCTAssertEqual(winback.count, 1, "a detractor with trigger_winback must fire the winback signal")
        XCTAssertEqual(winback[0].1["survey_id"] as? String, "srv_1")
        XCTAssertEqual(winback[0].1["sentiment"] as? String, "negative")
        XCTAssertEqual(winback[0].1["message"] as? String, "Come back — 50% off")
    }

    /// `on_neutral` was declared in the config model and read by nothing.
    func testNeutralFollowUpIsRead() throws {
        let (manager, events) = makeManager()
        let cfg = try config(onNeutral: "trigger_winback")

        manager.executeFollowUpAction(surveyId: "srv_1", config: cfg, answers: answer(7))

        let winback = events().filter { $0.0 == "survey_followup_winback" }
        XCTAssertEqual(winback.count, 1, "`actions.on_neutral` was NEVER read on iOS")
        XCTAssertEqual(winback[0].1["sentiment"] as? String, "neutral")
    }

    // MARK: - The two actions iOS did perform, which emitted no analytics

    func testPromptReviewEmitsFollowUpEvent() throws {
        let (manager, events) = makeManager()
        let cfg = try config(onPositive: "prompt_review")

        manager.executeFollowUpAction(surveyId: "srv_1", config: cfg, answers: answer(10))

        let fired = events().filter { $0.0 == "survey_followup_prompt_review" }
        XCTAssertEqual(fired.count, 1, "iOS performed the review prompt but emitted no follow-up event")
        XCTAssertEqual(fired[0].1["sentiment"] as? String, "positive")
        XCTAssertEqual(fired[0].1["survey_id"] as? String, "srv_1")
    }

    func testFeedbackFormEmitsFollowUpEvent() throws {
        let (manager, events) = makeManager()
        let cfg = try config(onNegative: "show_feedback_form")

        manager.executeFollowUpAction(surveyId: "srv_1", config: cfg, answers: answer(1))

        let fired = events().filter { $0.0 == "survey_followup_feedback_form" }
        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired[0].1["sentiment"] as? String, "negative")
    }

    // MARK: - Non-actions stay silent

    func testDismissAndAbsentActionsEmitNothing() throws {
        let (manager, events) = makeManager()

        // Promoter, whose bucket is configured to `dismiss` → no signal.
        manager.executeFollowUpAction(surveyId: "srv_1", config: try config(onPositive: "dismiss"), answers: answer(10))
        // Promoter, whose bucket has NO action configured → no signal.
        manager.executeFollowUpAction(surveyId: "srv_2", config: try config(onNegative: "trigger_winback"), answers: answer(10))

        XCTAssertTrue(
            events().filter { $0.0.hasPrefix("survey_followup_") }.isEmpty,
            "dismiss / unconfigured buckets must not raise a follow-up signal"
        )
    }
}
