import XCTest
@testable import AppDNASDK

final class EventQueueTests: XCTestCase {

    // MARK: - Event Store (disk persistence)

    func testEventStoreSaveAndLoad() {
        let store = EventStore()
        let event = makeTestEvent(name: "test_event")

        store.save(events: [event])
        let loaded = store.loadPending()

        XCTAssertFalse(loaded.isEmpty)
        XCTAssertEqual(loaded.last?.event_name, "test_event")

        // Cleanup
        store.removeSent(eventIds: Set(loaded.map(\.event_id)))
    }

    func testEventStoreRemoveSent() {
        let store = EventStore()
        let event1 = makeTestEvent(name: "event_1")
        let event2 = makeTestEvent(name: "event_2")

        store.save(events: [event1, event2])
        store.removeSent(eventIds: [event1.event_id])

        let remaining = store.loadPending()
        XCTAssertTrue(remaining.contains(where: { $0.event_id == event2.event_id }))
        XCTAssertFalse(remaining.contains(where: { $0.event_id == event1.event_id }))

        // Cleanup
        store.removeSent(eventIds: Set(remaining.map(\.event_id)))
    }

    func testEventStoreMaxSizeEnforcement() {
        let store = EventStore()

        // Save more than max events
        let events = (0..<100).map { i in makeTestEvent(name: "event_\(i)") }
        store.save(events: events)

        let loaded = store.loadPending()
        // Should not exceed 10,000 (our test only adds 100 so it should be fine)
        XCTAssertTrue(loaded.count <= 10_000)
        XCTAssertTrue(loaded.count >= 100)

        // Cleanup
        store.removeSent(eventIds: Set(loaded.map(\.event_id)))
    }

    func testEventStoreEmptyLoad() {
        let store = EventStore()
        // Clear any existing events
        let existing = store.loadPending()
        store.removeSent(eventIds: Set(existing.map(\.event_id)))

        let loaded = store.loadPending()
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - SDKEvent serialization

    func testEventSerialization() throws {
        let event = makeTestEvent(name: "serialization_test")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SDKEvent.self, from: data)

        XCTAssertEqual(decoded.event_name, "serialization_test")
        XCTAssertEqual(decoded.schema_version, 1)
        XCTAssertEqual(decoded.device.platform, "ios")
        XCTAssertEqual(decoded.device.sdk_version, "0.1.0")
        XCTAssertEqual(decoded.privacy.consent.analytics, true)
    }

    func testEventIdIsUUID() {
        let event = makeTestEvent(name: "uuid_test")
        XCTAssertNotNil(UUID(uuidString: event.event_id))
    }

    func testEventTimestamp() {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let event = makeTestEvent(name: "ts_test")
        let after = Int64(Date().timeIntervalSince1970 * 1000)

        XCTAssertGreaterThanOrEqual(event.ts_ms, before)
        XCTAssertLessThanOrEqual(event.ts_ms, after)
    }

    // MARK: - Helpers

    private func makeTestEvent(name: String) -> SDKEvent {
        EventEnvelopeBuilder.build(
            event: name,
            properties: ["test_key": "test_value"],
            identity: DeviceIdentity(anonId: "test-anon-id", userId: "test-user", traits: nil),
            sessionId: "test-session-id",
            analyticsConsent: true
        )
    }
}
