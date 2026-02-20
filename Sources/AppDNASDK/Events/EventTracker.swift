import Foundation

/// Builds SDKEvent envelopes from current identity and queues them.
final class EventTracker {
    private let identityManager: IdentityManager
    private weak var eventQueue: EventQueue?
    private var analyticsConsent = true

    init(identityManager: IdentityManager) {
        self.identityManager = identityManager
    }

    func setEventQueue(_ queue: EventQueue) {
        self.eventQueue = queue
    }

    /// Set analytics consent. When false, track() silently drops events.
    func setConsent(analytics: Bool) {
        analyticsConsent = analytics
    }

    /// Track an event. If consent is false, the event is silently dropped.
    func track(event: String, properties: [String: Any]?) {
        guard analyticsConsent else {
            Log.debug("Event '\(event)' dropped — analytics consent is false")
            return
        }

        let identity = identityManager.currentIdentity
        let sessionId = identityManager.sessionManager?.sessionId ?? "unknown"

        let sdkEvent = EventEnvelopeBuilder.build(
            event: event,
            properties: properties,
            identity: identity,
            sessionId: sessionId,
            analyticsConsent: analyticsConsent
        )

        eventQueue?.enqueue(sdkEvent)
        Log.debug("Tracked event: \(event)")
    }

    /// Track event with experiment exposure context attached.
    func trackWithExposures(event: String, properties: [String: Any]?, exposures: [ExperimentExposure]) {
        guard analyticsConsent else { return }

        let identity = identityManager.currentIdentity
        let sessionId = identityManager.sessionManager?.sessionId ?? "unknown"

        let sdkEvent = EventEnvelopeBuilder.build(
            event: event,
            properties: properties,
            identity: identity,
            sessionId: sessionId,
            analyticsConsent: analyticsConsent,
            experimentExposures: exposures
        )

        eventQueue?.enqueue(sdkEvent)
    }
}
