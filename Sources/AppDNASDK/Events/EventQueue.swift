import Foundation
import UIKit

/// Manages in-memory + disk event queue with automatic flushing.
final class EventQueue {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.eventqueue")
    private let apiClient: APIClient
    private let eventStore: EventStore
    private let batchSize: Int
    private let flushInterval: TimeInterval
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 4]

    private var pendingEvents: [SDKEvent] = []
    private var flushTimer: Timer?
    private var retryCount = 0

    init(
        apiClient: APIClient,
        eventStore: EventStore,
        eventTracker: EventTracker,
        batchSize: Int,
        flushInterval: TimeInterval
    ) {
        self.apiClient = apiClient
        self.eventStore = eventStore
        self.batchSize = batchSize
        self.flushInterval = flushInterval

        // Load persisted events from disk
        let persisted = eventStore.loadPending()
        if !persisted.isEmpty {
            self.pendingEvents = persisted
            Log.info("Loaded \(persisted.count) persisted events from disk")
        }

        // Start flush timer on main run loop
        DispatchQueue.main.async { [weak self] in
            self?.startFlushTimer()
        }

        // Observe app backgrounding for flush
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        flushTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// Add an event to the queue. Triggers threshold flush if batchSize reached.
    func enqueue(_ event: SDKEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingEvents.append(event)

            // Persist to disk immediately
            self.eventStore.save(events: [event])

            // Check threshold
            if self.pendingEvents.count >= self.batchSize {
                self.performFlush()
            }
        }
    }

    /// Force flush all pending events.
    func flush() {
        queue.async { [weak self] in
            self?.performFlush()
        }
    }

    // MARK: - Private

    private func startFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    @objc private func appDidEnterBackground() {
        flush()
    }

    private func performFlush() {
        // Already on queue
        guard !pendingEvents.isEmpty else { return }

        let batch = Array(pendingEvents.prefix(batchSize > 0 ? batchSize : pendingEvents.count))
        let eventIds = Set(batch.map(\.event_id))

        Log.debug("Flushing \(batch.count) events")

        let payload: [String: Any] = ["batch": batch.map { event -> [String: Any] in
            guard let data = try? JSONEncoder().encode(event),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return dict
        }]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            Log.error("Failed to serialize event batch")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let success = await self.apiClient.sendEvents(bodyData)

            self.queue.async {
                if success {
                    // Remove sent events from memory and disk
                    self.pendingEvents.removeAll { eventIds.contains($0.event_id) }
                    self.eventStore.removeSent(eventIds: eventIds)
                    self.retryCount = 0
                    Log.debug("Flush successful: \(batch.count) events delivered")
                } else {
                    if self.retryCount < self.maxRetries {
                        let delay = self.retryDelays[min(self.retryCount, self.retryDelays.count - 1)]
                        self.retryCount += 1
                        Log.debug("Flush failed, retrying in \(delay)s (attempt \(self.retryCount)/\(self.maxRetries))")
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.flush()
                        }
                    } else {
                        Log.warning("Max retries reached (\(self.maxRetries)). Events kept on disk for next session.")
                        self.retryCount = 0
                    }
                }
            }
        }
    }
}
