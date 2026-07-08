import XCTest
@testable import AppDNASDK

/// SPEC-428 — event-pipeline behavioral fixtures (`packages/sdk-shared-fixtures/events/*.fixture.json`).
///
/// The event pipeline (EventStore eviction, ClientSeqCounter monotonicity, DroppedEventsCounter,
/// event_id-stable redelivery) is NATIVE-owned per ADR-001, so iOS + Android assert these fixtures in
/// full; the Flutter/RN thin wrappers forward `track()` to native and defer these guarantees to the
/// native runners.
///
/// The driver replays each fixture's `pipeline.steps` against the REAL `EventStore` +
/// `EventEnvelopeBuilder` (assigns `client_seq`) + `DroppedEventsCounter`, with a mock server "sink"
/// that dedups by `event_id` (modelling the server dedup window), then asserts the observable output.
final class EventPipelineFixtureTests: XCTestCase {

    // MARK: - Fixture decoding

    struct Fixture: Decodable {
        let id: String
        let category: String
        let platforms: [String]
        let pipeline: Pipeline
    }
    struct Pipeline: Decodable {
        let config: Config?
        let steps: [Step]
        let expect: Expect
    }
    struct Config: Decodable {
        let max_events: Int?
        let max_bytes: Int?
        let redelivery_horizon_ms: Int?
    }
    struct Step: Decodable {
        let op: String
        let name: String?
        let count: Int?
        let ms: Int?
    }
    struct Expect: Decodable {
        let ingested_count: Int?
        let dropped_events_min: Int?
        let no_duplicate_event_id: Bool?
        let monotonic_client_seq: Bool?
        let ingested_order_key: String?
    }

    private static let seqKey = "ai.appdna.sdk.client_seq"
    private static let dropKey = "ai.appdna.sdk.dropped_events"

    // MARK: - Umbrella test

    func testEventPipelineFixtures() throws {
        let fixtures = try loadEventFixtures()
        XCTAssertFalse(fixtures.isEmpty, "No iOS event-pipeline fixtures found (packages/sdk-shared-fixtures/events)")
        for f in fixtures { runPipeline(f) }
        print("[EventPipeline] asserted \(fixtures.count) fixtures")
    }

    // MARK: - Driver

    private func resetCounters() {
        UserDefaults.standard.removeObject(forKey: Self.seqKey)
        UserDefaults.standard.removeObject(forKey: Self.dropKey)
    }

    private func makeEvent(_ name: String) -> SDKEvent {
        // Faithful path: the SAME builder production uses — assigns event_id (UUID) + client_seq (next()).
        EventEnvelopeBuilder.build(
            event: name,
            properties: nil,
            identity: DeviceIdentity(anonId: "spec428-anon", userId: nil, traits: nil),
            sessionId: "spec428-session",
            analyticsConsent: true
        )
    }

    private func runPipeline(_ f: Fixture) {
        resetCounters()
        let cfg = f.pipeline.config
        let cap = cfg?.max_events ?? 10_000
        let fileName = "spec428_\(f.id).json"
        // compactionInterval:1 → caps enforced on every save (so a small cap evicts deterministically).
        var store = EventStore(maxEvents: cap, compactionInterval: 1, fileName: fileName)
        store.clearAll()
        resetCounters() // clearAll may have run compaction paths; start from a clean ledger

        var online = true
        var ingestedIds = Set<String>()
        var ingested: [SDKEvent] = []
        var rawSent = 0
        var hadRedeliver = false

        func flush() {
            guard online else { return }
            let pending = store.loadPending()
            rawSent += pending.count // EVERY send, including redeliveries of still-unacked events
            for e in pending where !ingestedIds.contains(e.event_id) {
                ingestedIds.insert(e.event_id) // server dedups by STABLE event_id → each ingested once
                ingested.append(e)
            }
            // Deliberately do NOT removeSent — the queue stays "unacked" so a `redeliver` step re-sends
            // the SAME stored events (same event_id). If event_id were regenerated on resend, the sink
            // would fail to dedup → ingested_count would exceed the expected → the test fails. That is
            // what makes offline_redelivery_idempotent a real test of CL-2 event_id stability.
        }

        for step in f.pipeline.steps {
            switch step.op {
            case "track", "track_before_configure":
                let n = step.count ?? 1
                let base = step.name ?? "evt"
                for i in 0..<n {
                    let name = n > 1 ? "\(base)_\(i)" : base
                    store.save(events: [makeEvent(name)])
                }
            case "flush":
                flush()
            case "go_offline":
                online = false
            case "go_online":
                online = true
            case "restart":
                // persistence survives: same on-disk file + UserDefaults-backed ClientSeqCounter.
                store = EventStore(maxEvents: cap, compactionInterval: 1, fileName: fileName)
            case "redeliver":
                hadRedeliver = true
                flush() // re-sends the still-unacked events (same event_id) → sink must dedup them
            case "advance_time_ms":
                break
            default:
                XCTFail("[\(f.id)] unknown pipeline op: \(step.op)")
            }
        }

        let e = f.pipeline.expect
        if let want = e.ingested_count {
            XCTAssertEqual(ingested.count, want, "[\(f.id)] ingested_count")
        }
        if let minDrop = e.dropped_events_min {
            let dropped = DroppedEventsCounter.getAndReset()
            XCTAssertGreaterThanOrEqual(dropped, minDrop, "[\(f.id)] dropped_events_min (got \(dropped))")
        }
        if e.no_duplicate_event_id == true {
            XCTAssertEqual(Set(ingested.map { $0.event_id }).count, ingested.count, "[\(f.id)] no_duplicate_event_id")
        }
        if e.monotonic_client_seq == true {
            let seqs = ingested.compactMap { $0.context.client_seq }
            XCTAssertEqual(seqs.count, ingested.count, "[\(f.id)] every ingested event carries a client_seq")
            // Assert the INGESTED (returned) order is ALREADY ascending by client_seq — do NOT sort
            // first. This is what `ingested_order_key: client_seq` promises: the store returns events
            // in client_seq order, never wall-clock. A CL-6 intra-second reorder regression fails here.
            for i in 1..<max(seqs.count, 1) where i < seqs.count {
                XCTAssertGreaterThan(seqs[i], seqs[i - 1], "[\(f.id)] ingested client_seq strictly increasing IN RETURNED ORDER (index \(i))")
            }
        }
        // A `redeliver` step MUST actually re-send unacked events (else the idempotency guarantee is
        // never exercised): the raw send count exceeds the deduped ingested count only if the same
        // event_ids were re-sent and the sink collapsed them.
        if hadRedeliver {
            XCTAssertGreaterThan(rawSent, ingested.count, "[\(f.id)] redeliver must re-send unacked events (raw \(rawSent) vs ingested \(ingested.count))")
        }

        store.clearAll()
        resetCounters()
    }

    // MARK: - Loading

    private func loadEventFixtures() throws -> [Fixture] {
        guard let root = SharedFixtureTests.fixturesRootURL()?.appendingPathComponent("events") else {
            XCTFail("Could not locate packages/sdk-shared-fixtures/events")
            return []
        }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            XCTFail("Cannot enumerate \(root.path)")
            return []
        }
        let decoder = JSONDecoder()
        var out: [Fixture] = []
        for url in items where url.lastPathComponent.hasSuffix(".fixture.json") {
            let data = try Data(contentsOf: url)
            do {
                let f = try decoder.decode(Fixture.self, from: data)
                if f.category == "events" && f.platforms.contains("ios") { out.append(f) }
            } catch {
                XCTFail("Failed to decode \(url.lastPathComponent): \(error)")
            }
        }
        return out.sorted { $0.id < $1.id }
    }
}
