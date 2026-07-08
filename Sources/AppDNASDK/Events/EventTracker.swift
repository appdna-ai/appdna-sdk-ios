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

    /// Set analytics consent. When false, track() silently drops events AND any already-queued
    /// events are purged (SPEC-424 STEP-1a / CL-7).
    func setConsent(analytics: Bool) {
        analyticsConsent = analytics
        // Revoking consent MUST purge any queued-but-unsent events (in-memory + on-disk) WITHOUT
        // uploading — else the server-side consent gate is defeated by a later flush of events
        // captured while consent was true.
        if !analytics {
            eventQueue?.clear()
        }
    }

    /// Whether analytics consent is currently granted.
    var isConsentGranted: Bool { analyticsConsent }

    /// Track an event. If consent is false, the event is silently dropped.
    func track(event: String, properties: [String: Any]?, clientSeq: Int64? = nil) {
        guard analyticsConsent else {
            Log.debug("Event '\(event)' dropped — analytics consent is false")
            return
        }

        // SPEC-428 CL-1/D2: surface any silently-dropped events (cap/quota evictions) as a
        // _sdk_events_dropped meta-event so the loss is SERVER-VISIBLE. Drain before the real event;
        // guard against the meta-event itself re-triggering the drain.
        if event != "_sdk_events_dropped" {
            let dropped = DroppedEventsCounter.getAndReset()
            if dropped > 0 { emitDroppedMeta(count: dropped) }
        }

        let identity = identityManager.currentIdentity
        let sessionId = identityManager.sessionManager?.sessionId ?? "unknown"

        let sdkEvent = EventEnvelopeBuilder.build(
            event: event,
            properties: properties,
            identity: identity,
            sessionId: sessionId,
            analyticsConsent: analyticsConsent,
            clientSeq: clientSeq // SPEC-428 STEP-9: a pre-init event carries the seq it stamped at track() time
        )

        eventQueue?.enqueue(sdkEvent)
        Log.debug("Tracked event: \(event)")
    }

    /// SPEC-428 CL-1/D2: build + enqueue the _sdk_events_dropped meta-event directly (NOT via track(),
    /// to avoid re-entrancy). The count reflects events evicted since the last drain.
    private func emitDroppedMeta(count: Int) {
        let identity = identityManager.currentIdentity
        let sessionId = identityManager.sessionManager?.sessionId ?? "unknown"
        let ev = EventEnvelopeBuilder.build(
            event: "_sdk_events_dropped",
            properties: ["count": count],
            identity: identity,
            sessionId: sessionId,
            analyticsConsent: analyticsConsent
        )
        eventQueue?.enqueue(ev)
        Log.debug("Emitted _sdk_events_dropped meta-event (count=\(count))")
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
