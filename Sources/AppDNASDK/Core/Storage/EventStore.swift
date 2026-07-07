import Foundation

/// File-based event persistence in Application Support directory.
/// Ensures events survive app termination.
///
/// SPEC-067: Enforces both event count cap (10K) and disk quota (5 MB).
/// SPEC-428 CL-8/D8: storage is an APPEND-LOG (NDJSON — one event per line). `save()` appends in
/// O(1) amortized instead of the old O(n) full-file decode+append+encode on every `track()` (a
/// battery/CPU cliff at scale). Caps are enforced by periodic compaction, amortizing the O(n) rewrite.
final class EventStore {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.eventstore")
    private let fileURL: URL
    private static let maxEvents = 10_000
    /// SPEC-067: Maximum disk usage for event storage (5 MB).
    static let maxDiskBytes = 5 * 1024 * 1024
    /// SPEC-428 CL-8: compact (enforce caps by rewriting) at most every N appends → amortized O(1).
    private static let compactionInterval = 500
    private var appendsSinceCompaction = 0

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
        queue.sync { fileSize() }
    }

    /// SPEC-428 CL-8/D8: O(1) amortized append (was O(n) full read-modify-write per event). Caps are
    /// enforced by a periodic compaction (every `compactionInterval` appends, or immediately once the
    /// on-disk log exceeds the disk quota — a cheap O(1) size check).
    func save(events: [SDKEvent]) {
        queue.sync {
            appendToDisk(events)
            appendsSinceCompaction += events.count
            if appendsSinceCompaction >= Self.compactionInterval || fileSize() > Self.maxDiskBytes {
                compact()
            }
        }
    }

    /// Load all pending (unsent) events from disk.
    func loadPending() -> [SDKEvent] {
        queue.sync { loadFromDisk() }
    }

    /// Remove sent events by their IDs. O(n) rewrite — but flush is batch-level, not per-track.
    func removeSent(eventIds: Set<String>) {
        queue.sync {
            var existing = loadFromDisk()
            existing.removeAll { eventIds.contains($0.event_id) }
            writeToDisk(existing)
            appendsSinceCompaction = 0
        }
    }

    /// SPEC-424 STEP-1a (CL-7): purge ALL persisted events WITHOUT uploading them — analytics
    /// consent was revoked, so queued-but-unsent events must never be transmitted.
    func clearAll() {
        queue.sync {
            writeToDisk([])
            appendsSinceCompaction = 0
        }
    }

    // MARK: - Private

    private func fileSize() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    /// SPEC-428 CL-8: parse the NDJSON log (one event per line). A crash mid-append can leave a
    /// trailing partial line — unparseable lines are skipped, so the log is self-healing. Back-compat:
    /// an older single-JSON-array file decodes via the array path (then the next compaction rewrites
    /// it as NDJSON).
    private func loadFromDisk() -> [SDKEvent] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        if let arr = try? JSONDecoder().decode([SDKEvent].self, from: data) { return arr }
        let decoder = JSONDecoder()
        var events: [SDKEvent] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            if let ev = try? decoder.decode(SDKEvent.self, from: Data(line)) { events.append(ev) }
        }
        return events
    }

    /// SPEC-428 CL-8: append events as NDJSON lines (O(1) — seek to end + write). Creates the file on
    /// first write.
    private func appendToDisk(_ events: [SDKEvent]) {
        guard !events.isEmpty else { return }
        let encoder = JSONEncoder()
        var blob = Data()
        for event in events {
            guard let data = try? encoder.encode(event) else { continue }
            blob.append(data)
            blob.append(0x0A) // '\n'
        }
        guard !blob.isEmpty else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(blob)
        } else {
            // File doesn't exist yet — create it atomically with these lines.
            try? blob.write(to: fileURL, options: .atomic)
        }
    }

    /// Full rewrite as NDJSON (atomic). Used by compaction / removeSent / clearAll.
    private func writeToDisk(_ events: [SDKEvent]) {
        let encoder = JSONEncoder()
        var blob = Data()
        for event in events {
            guard let data = try? encoder.encode(event) else { continue }
            blob.append(data)
            blob.append(0x0A)
        }
        try? blob.write(to: fileURL, options: .atomic)
    }

    /// SPEC-428 CL-8: compaction enforces the count + disk caps by rewriting the log — the amortized
    /// O(n) work, run at most every `compactionInterval` appends. Dropped events are counted (CL-1).
    private func compact() {
        var events = loadFromDisk()
        let originalCount = events.count
        if events.count > Self.maxEvents {
            events = Array(events.suffix(Self.maxEvents))
        }
        writeToDisk(events)

        // SPEC-067: disk-quota — drop oldest 10% until under limit.
        while fileSize() > Self.maxDiskBytes && !events.isEmpty {
            let dropCount = max(events.count / 10, 1)
            events = Array(events.dropFirst(dropCount))
            writeToDisk(events)
        }

        let dropped = originalCount - events.count
        if dropped > 0 {
            DroppedEventsCounter.increment(dropped) // SPEC-428 CL-1/D2: count the loss (never silent)
            Log.warning("Event store compaction dropped \(dropped) oldest events (count/disk caps enforced)")
        }
        appendsSinceCompaction = 0
    }
}

/// SPEC-428 CL-1/D2 — durable counter of events dropped by a cap/quota eviction. Persisted in
/// UserDefaults so a restart never loses the count; drained by EventTracker into a
/// `_sdk_events_dropped` meta-event so the loss is SERVER-VISIBLE, not a silent Log.warning.
enum DroppedEventsCounter {
    private static let key = "ai.appdna.sdk.dropped_events"
    private static let lock = NSLock()

    static func increment(_ n: Int) {
        guard n > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + n, forKey: key)
    }

    /// Atomically read + reset. The caller emits the meta-event with the returned count.
    static func getAndReset() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = UserDefaults.standard.integer(forKey: key)
        if current > 0 { UserDefaults.standard.set(0, forKey: key) }
        return current
    }
}
