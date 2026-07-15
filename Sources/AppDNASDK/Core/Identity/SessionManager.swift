import Foundation
import UIKit

/// Tracks app sessions based on foreground/background lifecycle.
/// A new session starts on cold launch or after >30 minutes of inactivity.
final class SessionManager {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.session")
    private let eventTracker: EventTracker

    private static let sessionTimeoutInterval: TimeInterval = 30 * 60 // 30 minutes
    private static let lastActiveKey = "ai.appdna.sdk.lastActiveAt"
    /// Per-install session counter. SurveyManager READS this key for `min_sessions` triggers and for the
    /// survey-response `session_count`, but nothing WROTE it — so every min_sessions trigger was
    /// unsatisfiable and every response reported 0. Incremented on each new session below.
    static let sessionCountKey = "ai.appdna.sdk.session_count"

    private var _sessionId: String = UUID().uuidString.lowercased()

    var sessionId: String {
        queue.sync { _sessionId }
    }

    init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker

        // Check if we need a new session (cold start or >30 min gap)
        let now = Date()
        if let lastActive = UserDefaults.standard.object(forKey: Self.lastActiveKey) as? Date,
           now.timeIntervalSince(lastActive) < Self.sessionTimeoutInterval {
            // Resume existing session — just track app_open
            Log.debug("Resuming session (last active \(lastActive))")
        } else {
            // New session
            startNewSession()
        }

        // Observe app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func startNewSession() {
        queue.sync {
            _sessionId = UUID().uuidString.lowercased()
        }
        // Bump the per-install session counter the survey engine reads (see sessionCountKey).
        let d = UserDefaults.standard
        d.set(d.integer(forKey: Self.sessionCountKey) + 1, forKey: Self.sessionCountKey)
        eventTracker.track(event: "session_start", properties: nil)
        Log.info("New session started: \(sessionId)")
    }

    private func updateLastActive() {
        UserDefaults.standard.set(Date(), forKey: Self.lastActiveKey)
    }

    @objc private func appDidEnterForeground() {
        let now = Date()
        let lastActive = UserDefaults.standard.object(forKey: Self.lastActiveKey) as? Date

        if let lastActive, now.timeIntervalSince(lastActive) >= Self.sessionTimeoutInterval {
            // End old session, start new one
            eventTracker.track(event: "session_end", properties: nil)
            startNewSession()
        }

        eventTracker.track(event: "app_open", properties: nil)
        updateLastActive()
    }

    @objc private func appDidEnterBackground() {
        eventTracker.track(event: "app_close", properties: nil)
        updateLastActive()
    }
}
