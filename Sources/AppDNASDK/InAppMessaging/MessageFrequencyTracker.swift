import Foundation

/// Tracks message display frequency: persisted (once, max_times) and session-level.
final class MessageFrequencyTracker {
    private let defaults = UserDefaults.standard
    private let prefix = "ai.appdna.sdk.msg_freq."

    /// In-memory set for once_per_session tracking.
    private var sessionShownIds: Set<String> = []

    // MARK: - Check

    /// Returns true if the message can be shown based on its frequency rules.
    func canShow(messageId: String, frequency: MessageFrequency, maxDisplays: Int?) -> Bool {
        switch frequency {
        case .once:
            return !hasBeenShown(messageId: messageId)
        case .once_per_session:
            return !sessionShownIds.contains(messageId)
        case .every_time:
            return true
        case .max_times:
            guard let max = maxDisplays else { return true }
            return displayCount(messageId: messageId) < max
        }
    }

    // MARK: - Record

    /// Record that a message was shown.
    func recordShown(messageId: String, frequency: MessageFrequency) {
        switch frequency {
        case .once:
            defaults.set(true, forKey: "\(prefix)\(messageId).shown")
        case .once_per_session:
            sessionShownIds.insert(messageId)
        case .every_time:
            break
        case .max_times:
            let count = displayCount(messageId: messageId)
            defaults.set(count + 1, forKey: "\(prefix)\(messageId).count")
        }
    }

    /// Reset session-level tracking (called on new session).
    func resetSession() {
        sessionShownIds.removeAll()
    }

    // MARK: - Private

    private func hasBeenShown(messageId: String) -> Bool {
        defaults.bool(forKey: "\(prefix)\(messageId).shown")
    }

    private func displayCount(messageId: String) -> Int {
        defaults.integer(forKey: "\(prefix)\(messageId).count")
    }
}
