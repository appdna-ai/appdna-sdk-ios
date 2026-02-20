import Foundation

/// Tracks survey display frequency: persisted (once, max_times) and session-level.
final class SurveyFrequencyTracker {
    private let defaults = UserDefaults.standard
    private let prefix = "ai.appdna.sdk.survey_freq."

    /// In-memory set for once_per_session tracking.
    private var sessionShownIds: Set<String> = []

    // MARK: - Check

    /// Returns true if the survey can be shown based on its frequency rules.
    func canShow(surveyId: String, frequency: MessageFrequency, maxDisplays: Int?) -> Bool {
        switch frequency {
        case .once:
            return !hasBeenShown(surveyId: surveyId)
        case .once_per_session:
            return !sessionShownIds.contains(surveyId)
        case .every_time:
            return true
        case .max_times:
            guard let max = maxDisplays else { return true }
            return displayCount(surveyId: surveyId) < max
        }
    }

    // MARK: - Record

    /// Record that a survey was shown.
    func recordDisplay(surveyId: String) {
        sessionShownIds.insert(surveyId)
        // Persist display count
        let count = displayCount(surveyId: surveyId)
        defaults.set(count + 1, forKey: "\(prefix)\(surveyId).count")
        // Mark as shown (for .once)
        defaults.set(true, forKey: "\(prefix)\(surveyId).shown")
    }

    /// Reset session-level tracking (called on new session).
    func resetSession() {
        sessionShownIds.removeAll()
    }

    // MARK: - Private

    private func hasBeenShown(surveyId: String) -> Bool {
        defaults.bool(forKey: "\(prefix)\(surveyId).shown")
    }

    private func displayCount(surveyId: String) -> Int {
        defaults.integer(forKey: "\(prefix)\(surveyId).count")
    }
}
