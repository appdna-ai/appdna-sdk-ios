import Foundation
import UIKit

/// Manages survey trigger evaluation, display queue, frequency tracking, and presentation.
final class SurveyManager {
    private let remoteConfigManager: RemoteConfigManager
    private let eventTracker: EventTracker
    private let apiClient: APIClient?
    private let frequencyTracker = SurveyFrequencyTracker()
    private let renderer = SurveyRenderer()
    private var isPresenting = false

    private var surveyConfigs: [String: SurveyConfig] = [:]

    init(remoteConfigManager: RemoteConfigManager, eventTracker: EventTracker, apiClient: APIClient? = nil) {
        self.remoteConfigManager = remoteConfigManager
        self.eventTracker = eventTracker
        self.apiClient = apiClient
    }

    /// Present a specific survey by ID.
    func present(surveyId: String) {
        guard let config = surveyConfigs[surveyId] else {
            Log.warning("Survey config not found for id: \(surveyId)")
            return
        }
        presentSurvey(surveyId: surveyId, config: config, triggerEvent: "manual")
    }

    /// Called by RemoteConfigManager when Firestore config/surveys updates.
    func updateConfigs(_ configs: [String: SurveyConfig]) {
        self.surveyConfigs = configs
    }

    /// Called by EventTracker on every tracked event.
    func onEvent(eventName: String, properties: [String: Any]?) {
        guard !isPresenting else { return }

        for (surveyId, config) in surveyConfigs {
            // 1. Event name match
            guard config.trigger_rules.event == eventName else { continue }

            // 2. Conditions evaluation
            guard evaluateConditions(config.trigger_rules.conditions, properties: properties ?? [:]) else { continue }

            // 3. Frequency check
            guard frequencyTracker.canShow(
                surveyId: surveyId,
                frequency: config.trigger_rules.frequency,
                maxDisplays: config.trigger_rules.max_displays
            ) else { continue }

            // 4. Love score range check
            if let range = config.trigger_rules.love_score_range {
                let loveScore = UserDefaults.standard.integer(forKey: "ai.appdna.sdk.love_score")
                guard loveScore >= range.min && loveScore <= range.max else { continue }
            }

            // 5. Min sessions check
            guard meetsMinSessions(config.trigger_rules.min_sessions) else { continue }

            // 5. Present with optional delay
            let delay = config.trigger_rules.delay_seconds ?? 0
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) { [weak self] in
                    self?.presentSurvey(surveyId: surveyId, config: config, triggerEvent: eventName)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.presentSurvey(surveyId: surveyId, config: config, triggerEvent: eventName)
                }
            }
            break // Only show one survey per event
        }
    }

    /// Reset session-level frequency tracking.
    func resetSession() {
        frequencyTracker.resetSession()
    }

    // MARK: - Presentation

    private func presentSurvey(surveyId: String, config: SurveyConfig, triggerEvent: String) {
        guard !isPresenting else { return }
        isPresenting = true

        // Track survey shown
        eventTracker.track(event: "survey_shown", properties: [
            "survey_id": surveyId,
            "survey_type": config.survey_type,
            "trigger_event": triggerEvent,
        ])

        renderer.present(config: config, onQuestionAnswered: { [weak self] surveyName, question, answer in
            self?.eventTracker.track(event: "survey_question_answered", properties: [
                "survey_id": surveyId,
                "question_id": question.id,
                "question_type": question.type,
                "answer": answer.answer,
            ])
        }) { [weak self] result in
            guard let self else { return }
            self.isPresenting = false

            switch result {
            case .completed(let answers):
                self.frequencyTracker.recordDisplay(surveyId: surveyId)
                self.trackSurveyCompleted(surveyId: surveyId, config: config, answers: answers)
                self.submitResponse(surveyId: surveyId, config: config, answers: answers)
                self.executeFollowUpAction(config: config, answers: answers)

            case .dismissed(let answeredCount):
                self.frequencyTracker.recordDisplay(surveyId: surveyId)
                self.eventTracker.track(event: "survey_dismissed", properties: [
                    "survey_id": surveyId,
                    "questions_answered": answeredCount,
                ])
            }
        }
    }

    // MARK: - Event tracking

    private func trackSurveyCompleted(surveyId: String, config: SurveyConfig, answers: [SurveyAnswer]) {
        let answersArray = answers.map { $0.asDictionary }
        eventTracker.track(event: "survey_completed", properties: [
            "survey_id": surveyId,
            "survey_type": config.survey_type,
            "answers": answersArray,
        ])
    }

    // MARK: - Response submission

    private func submitResponse(surveyId: String, config: SurveyConfig, answers: [SurveyAnswer]) {
        let body: [String: Any] = [
            "survey_id": surveyId,
            "survey_type": config.survey_type,
            "answers": answers.map { $0.asDictionary },
            "context": [
                "sdk_version": AppDNA.sdkVersion,
                "platform": "ios",
                "device": UIDevice.current.model,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                "session_count": UserDefaults.standard.integer(forKey: "ai.appdna.sdk.session_count"),
                "days_since_install": self.daysSinceInstall(),
            ],
        ]

        apiClient?.post(path: "/api/v1/feedback/responses", body: body) { result in
            switch result {
            case .success:
                Log.debug("Survey response submitted for \(surveyId)")
            case .failure(let error):
                Log.error("Failed to submit survey response: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Follow-up actions

    private func executeFollowUpAction(config: SurveyConfig, answers: [SurveyAnswer]) {
        let sentiment = determineSentiment(config: config, answers: answers)
        guard let actions = config.follow_up_actions else { return }

        switch sentiment {
        case .positive:
            if actions.on_positive?.action == "prompt_review" {
                ReviewPromptManager.shared.triggerReview()
            }
        case .negative:
            if actions.on_negative?.action == "show_feedback_form" {
                presentFeedbackForm(message: actions.on_negative?.message)
            }
        case .neutral:
            break
        }
    }

    private func presentFeedbackForm(message: String?) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
                  var rootVC = windowScene.windows
                .first(where: { $0.isKeyWindow })?
                .rootViewController else { return }

            while let presented = rootVC.presentedViewController {
                rootVC = presented
            }
            let topVC = rootVC

            let alert = UIAlertController(
                title: message ?? "We'd love your feedback",
                message: "What could we do better?",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = "Tell us what you think..."
            }
            alert.addAction(UIAlertAction(title: "Submit", style: .default) { [weak self] _ in
                let feedback = alert.textFields?.first?.text ?? ""
                self?.eventTracker.track(event: "feedback_form_submitted", properties: [
                    "feedback": feedback,
                ])
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.eventTracker.track(event: "feedback_form_dismissed", properties: nil)
            })
            topVC.present(alert, animated: true)
        }
    }

    private func determineSentiment(config: SurveyConfig, answers: [SurveyAnswer]) -> SurveySentiment {
        // NPS: 9-10 = positive, 0-6 = negative, 7-8 = neutral
        if config.survey_type == "nps", let first = answers.first, let score = first.answer as? Int {
            if score >= 9 { return .positive }
            if score <= 6 { return .negative }
            return .neutral
        }

        // CSAT/Rating: >= 4 (out of 5) = positive, <= 2 = negative
        if ["csat", "rating"].contains(config.survey_type), let first = answers.first, let rating = first.answer as? Int {
            if rating >= 4 { return .positive }
            if rating <= 2 { return .negative }
            return .neutral
        }

        // Emoji: last 2 = positive, first 2 = negative
        if config.survey_type == "emoji_scale" || answers.first?.answer is String {
            let emojis = ["😡", "😕", "😐", "😊", "😍"]
            if let first = answers.first, let emoji = first.answer as? String,
               let idx = emojis.firstIndex(of: emoji) {
                if idx >= 3 { return .positive }
                if idx <= 1 { return .negative }
                return .neutral
            }
        }

        return .neutral
    }

    // MARK: - Condition evaluation (shared with MessageManager pattern)

    private func evaluateConditions(_ conditions: [TriggerCondition]?, properties: [String: Any]) -> Bool {
        guard let conditions, !conditions.isEmpty else { return true }

        return conditions.allSatisfy { condition in
            guard let propValue = properties[condition.field] else { return false }
            return evaluateOperator(condition.operator, propValue: propValue, condValue: condition.value.value)
        }
    }

    private func evaluateOperator(_ op: TriggerCondition.ConditionOperator, propValue: Any, condValue: Any) -> Bool {
        switch op {
        case .eq:
            return "\(propValue)" == "\(condValue)"
        case .gte:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum >= cNum
        case .lte:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum <= cNum
        case .gt:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum > cNum
        case .lt:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum < cNum
        case .contains:
            return "\(propValue)".contains("\(condValue)")
        }
    }

    private func toDouble(_ value: Any) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    // MARK: - Min sessions

    private func meetsMinSessions(_ minSessions: Int?) -> Bool {
        guard let min = minSessions, min > 0 else { return true }
        let sessionCount = UserDefaults.standard.integer(forKey: "ai.appdna.sdk.session_count")
        return sessionCount >= min
    }

    private func daysSinceInstall() -> Int {
        let installKey = "ai.appdna.sdk.install_date"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: installKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: installKey)
        }
        let installTs = defaults.double(forKey: installKey)
        let elapsed = Date().timeIntervalSince1970 - installTs
        return max(0, Int(elapsed / 86400))
    }
}
