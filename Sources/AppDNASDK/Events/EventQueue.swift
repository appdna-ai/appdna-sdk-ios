import Foundation
import UIKit

/// SPEC-428 CL-9/D4 — process-wide single upload owner. The in-process flush (EventQueue) and the
/// background uploader (BackgroundUploader) must be mutually exclusive, else both POST the same rows
/// concurrently (DUP). A non-blocking claim: whoever holds it uploads; the other skips this cycle.
enum EventUploadCoordinator {
    private static let lock = NSLock()
    private static var uploading = false

    static func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if uploading { return false }
        uploading = true
        return true
    }

    static func release() {
        lock.lock()
        defer { lock.unlock() }
        uploading = false
    }
}

/// Manages in-memory + disk event queue with automatic flushing.
/// SPEC-067: Adaptive batch sizing based on network conditions.
final class EventQueue {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.eventqueue")
    private let apiClient: APIClient
    private let eventStore: EventStore
    private let baseBatchSize: Int
    private let flushInterval: TimeInterval
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 4]
    // SPEC-428 CL-2/D5: client redelivery horizon — never re-send an event older than this (past the
    // server dedup window it would double-count). Compiled default 7d, tracking SPEC-426's horizon.
    private let redeliveryHorizonMs: Int64 = 7 * 24 * 60 * 60 * 1000

    private var pendingEvents: [SDKEvent] = []
    private var flushTimer: Timer?
    private var retryCount = 0
    private var consecutiveFailures = 0
    // SPEC-428 CL-5/D4: single-flush-authority guard (mirrors Android's flushMutex). Set on the serial
    // `queue`; a second performFlush while a batch is in-flight would grab the same prefix + POST it
    // twice (removal happens only AFTER the async upload awaits).
    private var isFlushing = false
    private let maxConsecutiveFailures = 5
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// SPEC-067: Returns the current effective batch size based on network conditions.
    private var effectiveBatchSize: Int {
        NetworkMonitor.shared.adaptiveBatchSize
    }

    init(
        apiClient: APIClient,
        eventStore: EventStore,
        eventTracker: EventTracker,
        batchSize: Int,
        flushInterval: TimeInterval
    ) {
        self.apiClient = apiClient
        self.eventStore = eventStore
        self.baseBatchSize = batchSize
        self.flushInterval = flushInterval

        // Load persisted events from disk
        let persisted = eventStore.loadPending()
        if !persisted.isEmpty {
            // SPEC-428 P1: trim the in-memory window to maxInMemoryEvents on load — disk keeps them
            // all, RAM holds only the most-recent 1000. iOS previously assigned the full disk load
            // (up to the 10k disk cap) into RAM after restart, violating its own maxInMemoryEvents
            // (Android already trims after load).
            self.pendingEvents = persisted.count > maxInMemoryEvents
                ? Array(persisted.suffix(maxInMemoryEvents))
                : persisted
            Log.info("Loaded \(persisted.count) persisted events from disk (\(self.pendingEvents.count) held in memory)")
        }

        // Start flush timer on main run loop
        DispatchQueue.main.async { [weak self] in
            self?.startFlushTimer()
        }

        // Observe app backgrounding for flush + background upload
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

    /// Maximum in-memory events. Beyond this, oldest events are dropped (still on disk).
    private let maxInMemoryEvents = 1000

    /// Add an event to the queue. Triggers threshold flush if adaptive batch size reached.
    func enqueue(_ event: SDKEvent) {
        queue.async { [weak self] in
            guard let self else { return }

            // Cap in-memory events to prevent memory pressure
            if self.pendingEvents.count >= self.maxInMemoryEvents {
                self.pendingEvents.removeFirst(self.pendingEvents.count - self.maxInMemoryEvents + 1)
            }
            self.pendingEvents.append(event)

            // Persist to disk immediately
            self.eventStore.save(events: [event])

            // SPEC-067: Check adaptive threshold
            let currentBatchSize = self.effectiveBatchSize
            if currentBatchSize > 0 && self.pendingEvents.count >= currentBatchSize {
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

    /// SPEC-424 STEP-1a (CL-7): purge ALL pending events (in-memory + on-disk) WITHOUT uploading —
    /// called when analytics consent is revoked so queued-but-unsent events are never transmitted.
    /// A server-side consent gate is defeated if the SDK later flushes events captured while consent
    /// was true, so revoke must drop them at the source.
    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingEvents.removeAll()
            self.eventStore.clearAll()
            Log.info("Event queue purged — analytics consent revoked")
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
        // Guard against duplicate background tasks
        guard backgroundTask == .invalid else { return }

        // Request background time to ensure flush completes before suspension
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        flush()
        // End background task after flush dispatch completes on the same serial queue
        queue.async { [weak self] in
            self?.endBackgroundTask()
        }
        // SPEC-067: Schedule background upload for remaining events
        BackgroundUploader.shared?.scheduleUploadIfNeeded()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// SPEC-428 CL-2/D5: drop events past the redelivery horizon before any flush — re-sending them
    /// past the server dedup window would double-count. The drop is counted (CL-1).
    private func pruneStaleEvents() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // Remove stale from the in-memory working set only (NO count here); eventStore.pruneStale is the
        // SINGLE, meta-aware count source (the persisted copies of these events live on disk), so the loss
        // metric can't be double-incremented by the in-process flush AND the background upload both pruning.
        pendingEvents.removeAll { nowMs - $0.ts_ms > redeliveryHorizonMs }
        eventStore.pruneStale(horizonMs: redeliveryHorizonMs)
    }

    private func performFlush() {
        // Already on queue
        pruneStaleEvents()
        guard !pendingEvents.isEmpty else { return }

        // Stop hammering the server after repeated failures — wait for next app session
        if consecutiveFailures >= maxConsecutiveFailures {
            Log.debug("Paused event flush after \(consecutiveFailures) consecutive failures. Events saved to disk.")
            return
        }

        // SPEC-067: Skip flush if no network
        let currentBatchSize = effectiveBatchSize
        guard currentBatchSize > 0 else {
            Log.debug("No network — skipping flush, \(pendingEvents.count) events queued")
            return
        }

        // SPEC-428 CL-5: only one flush may be in-flight — otherwise a timer/threshold/retry/background
        // flush grabs the same prefix before the async removal and POSTs it twice.
        guard !isFlushing else {
            Log.debug("Flush already in progress — skipping overlapping flush")
            return
        }
        isFlushing = true

        // SPEC-428 CL-9/D4: also claim the cross-path upload owner so the background uploader cannot
        // POST the same batch concurrently. If the background path holds it, back off this cycle.
        guard EventUploadCoordinator.tryAcquire() else {
            isFlushing = false
            Log.debug("Flush deferred — background uploader is active")
            return
        }

        let batch = Array(pendingEvents.prefix(currentBatchSize > 0 ? currentBatchSize : pendingEvents.count))
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
            isFlushing = false // CL-5: release the guard on this early-return path
            EventUploadCoordinator.release() // CL-9: release the cross-path claim
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
                    self.consecutiveFailures = 0
                    Log.debug("Flush successful: \(batch.count) events delivered")
                } else if self.apiClient.eventUploadPermanentlyFailed {
                    // 401/400 — retrying won't help. Pause immediately.
                    self.consecutiveFailures = self.maxConsecutiveFailures
                    self.retryCount = 0
                    Log.error("Event uploads permanently failed (invalid key or payload). Paused until next session.")
                } else {
                    if self.retryCount < self.maxRetries {
                        let delay = self.retryDelays[min(self.retryCount, self.retryDelays.count - 1)]
                        self.retryCount += 1
                        Log.debug("Flush failed, retrying in \(delay)s (attempt \(self.retryCount)/\(self.maxRetries))")
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.flush()
                        }
                    } else {
                        self.consecutiveFailures += 1
                        self.retryCount = 0
                        if self.consecutiveFailures >= self.maxConsecutiveFailures {
                            Log.warning("Too many consecutive flush failures (\(self.consecutiveFailures)). Event uploads paused until next session.")
                        } else {
                            Log.warning("Max retries reached (\(self.maxRetries)). Will try again on next flush cycle.")
                        }
                    }
                }
                // SPEC-428 CL-5: release the single-flush guard once this batch's upload is resolved
                // (success removal, permanent-fail pause, or retry scheduled).
                self.isFlushing = false
                EventUploadCoordinator.release() // SPEC-428 CL-9: release the cross-path upload claim
            }
        }
    }
}
