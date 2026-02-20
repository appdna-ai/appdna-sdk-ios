import Foundation

/// File-based event persistence in Application Support directory.
/// Ensures events survive app termination.
final class EventStore {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.eventstore")
    private let fileURL: URL
    private static let maxEvents = 10_000

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ai.appdna.sdk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pending_events.json")
    }

    /// Append events to disk storage.
    func save(events: [SDKEvent]) {
        queue.sync {
            var existing = loadFromDisk()
            existing.append(contentsOf: events)

            // Enforce max limit — drop oldest
            if existing.count > Self.maxEvents {
                let overflow = existing.count - Self.maxEvents
                Log.warning("Event store overflow: dropping \(overflow) oldest events")
                existing = Array(existing.suffix(Self.maxEvents))
            }

            writeToDisk(existing)
        }
    }

    /// Load all pending (unsent) events from disk.
    func loadPending() -> [SDKEvent] {
        queue.sync { loadFromDisk() }
    }

    /// Remove sent events by their IDs.
    func removeSent(eventIds: Set<String>) {
        queue.sync {
            var existing = loadFromDisk()
            existing.removeAll { eventIds.contains($0.event_id) }
            writeToDisk(existing)
        }
    }

    // MARK: - Private

    private func loadFromDisk() -> [SDKEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SDKEvent].self, from: data)) ?? []
    }

    private func writeToDisk(_ events: [SDKEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
