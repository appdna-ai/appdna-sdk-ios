import Foundation
import BackgroundTasks
import UIKit

/// SPEC-067: Background event upload using BGTaskScheduler.
/// Ensures queued events are delivered even when the app is backgrounded.
final class BackgroundUploader {
    /// Task identifier — must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "ai.appdna.sdk.eventUpload"

    /// Shared instance, set during SDK init.
    static var shared: BackgroundUploader?

    private weak var apiClient: APIClient?
    private let eventStore: EventStore
    private var retryCount = 0
    private let maxRetries = 3

    init(apiClient: APIClient, eventStore: EventStore) {
        self.apiClient = apiClient
        self.eventStore = eventStore
    }

    /// Register the background task with the system.
    /// Must be called during application(_:didFinishLaunchingWithOptions:) or SDK init.
    func registerBackgroundTask() {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.taskIdentifier,
                using: nil
            ) { [weak self] task in
                guard let processingTask = task as? BGProcessingTask else { return }
                self?.handleBackgroundTask(processingTask)
            }
            Log.debug("Registered background upload task: \(Self.taskIdentifier)")
        }
    }

    /// Schedule a background upload if there are pending events.
    func scheduleUploadIfNeeded() {
        guard #available(iOS 13.0, *) else { return }

        let pendingCount = eventStore.loadPending().count
        guard pendingCount > 0 else {
            Log.debug("No pending events — skipping background upload schedule")
            return
        }

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.info("Scheduled background upload for \(pendingCount) pending events")
        } catch {
            Log.warning("Failed to schedule background upload: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    @available(iOS 13.0, *)
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        Log.info("Background upload task started")

        task.expirationHandler = {
            Log.warning("Background upload task expired")
            task.setTaskCompleted(success: false)
        }

        Task { [weak self] in
            guard let self, let apiClient = self.apiClient else {
                task.setTaskCompleted(success: false)
                return
            }

            let events = self.eventStore.loadPending()
            guard !events.isEmpty else {
                task.setTaskCompleted(success: true)
                return
            }

            // Send events in batches using adaptive batch size
            let batchSize = NetworkMonitor.shared.adaptiveBatchSize
            guard batchSize > 0 else {
                // No network — reschedule
                self.scheduleUploadIfNeeded()
                task.setTaskCompleted(success: false)
                return
            }

            let batch = Array(events.prefix(batchSize))
            let payload: [String: Any] = ["batch": batch.compactMap { event -> [String: Any]? in
                guard let data = try? JSONEncoder().encode(event),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return dict
            }]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
                task.setTaskCompleted(success: false)
                return
            }

            let success = await apiClient.sendEvents(bodyData)

            if success {
                let eventIds = Set(batch.map(\.event_id))
                self.eventStore.removeSent(eventIds: eventIds)
                self.retryCount = 0
                Log.info("Background upload successful: \(batch.count) events")

                // If more events remain, reschedule
                if events.count > batch.count {
                    self.scheduleUploadIfNeeded()
                }
            } else {
                self.retryCount += 1
                if self.retryCount < self.maxRetries {
                    self.scheduleUploadIfNeeded()
                } else {
                    self.retryCount = 0
                    Log.warning("Background upload max retries reached")
                }
            }

            task.setTaskCompleted(success: success)
        }
    }
}
