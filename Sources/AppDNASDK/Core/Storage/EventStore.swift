import Foundation

/// File-based event persistence in Application Support directory.
/// Ensures events survive app termination.
/// SPEC-067: Enforces both event count cap (10K) and disk quota (5 MB).
final class EventStore {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.eventstore")
    private let fileURL: URL
    private static let maxEvents = 10_000
    /// SPEC-067: Maximum disk usage for event storage (5 MB).
    static let maxDiskBytes = 5 * 1024 * 1024

    init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback to temp directory if Application Support is unavailable
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ai.appdna.sdk", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("pending_events.json")
            return
        }
        let dir = appSupport.appendingPathComponent("ai.appdna.sdk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pending_events.json")
    }

    /// Returns the current disk size of the event store file in bytes.
    var diskSizeBytes: Int {
        queue.sync {
            (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        }
    }

    /// Append events to disk storage.
    func save(events: [SDKEvent]) {
        queue.sync {
            var existing = loadFromDisk()
            existing.append(contentsOf: events)

            // Enforce max event count — drop oldest
            if existing.count > Self.maxEvents {
                let overflow = existing.count - Self.maxEvents
                Log.warning("Event store overflow: dropping \(overflow) oldest events (count cap)")
                existing = Array(existing.suffix(Self.maxEvents))
            }

            writeToDisk(existing)

            // SPEC-067: Enforce disk quota — drop oldest until under limit
            enforceDiskQuota(&existing)
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

    /// SPEC-067: Drop oldest events until file size is under disk quota.
    private func enforceDiskQuota(_ events: inout [SDKEvent]) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > Self.maxDiskBytes else {
            return
        }

        let originalCount = events.count
        // Remove oldest events in chunks of 10% until under quota
        while events.count > 0 {
            let dropCount = max(events.count / 10, 1)
            events = Array(events.dropFirst(dropCount))
            writeToDisk(events)

            let newSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if newSize <= Self.maxDiskBytes { break }
        }

        let dropped = originalCount - events.count
        if dropped > 0 {
            Log.warning("Event store disk quota enforced: dropped \(dropped) oldest events (\(Self.maxDiskBytes / 1024)KB limit)")
        }
    }
}
