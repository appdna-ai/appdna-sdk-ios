import XCTest
@testable import AppDNASDK

/**
 SPEC-070-B AC-35 — resilience behavioral fixtures (packages/sdk-shared-fixtures/resilience/).

 These are the upload/queue SURVIVAL contracts, and every one of them lives below the bridge: a
 wrapper cannot observe an HTTP status, a `Retry-After` header, or a prune decision. So — exactly like
 `events` — the category is native-only and iOS + Android assert the SAME fixture table.

 Each `contract` maps to a PURE seam, which is why this is a table test rather than an HTTP mock:
   - transient_status → `APIClient.transientStatusCodes`  (Android: ApiClient.TRANSIENT_STATUS_CODES)
   - retry_after      → `APIClient.parseRetryAfter`       (Android: ApiClient.parseRetryAfter)
   - stale_horizon    → `EventStore.isStale`              (Android: EventDatabase.isStale)

 A fixture whose `contract` this runner does not know FAILS. It is never skipped — a silently skipped
 resilience fixture is the coverage theater AC-35 exists to remove.
 */
final class ResilienceFixtureTests: XCTestCase {

    /**
     `retry_after` needs three states per key, not two: KEY ABSENT (the fixture forgot to state an
     expectation — a bug), KEY PRESENT AS NULL (the header is absent / the delay is refused — a real
     case we must assert), and KEY PRESENT WITH A VALUE.

     A `String??` with synthesized Decodable cannot express that: Swift synthesizes `decodeIfPresent`,
     which maps a JSON `null` to `.none` — exactly the same as a missing key. So `.some(nil)` never
     occurs, the "expected refusal" rows collapse into "malformed fixture", and the suite fails.
     (Android's `JSONObject.isNull` distinguishes them for free, which is why only iOS hit this.)
     `contains` + `decodeNil` is the only way to tell the three apart.
     */
    private struct Case: Decodable {
        let status: Int?
        let transient: Bool?
        let headerPresent: Bool
        let header: String?
        let secondsPresent: Bool
        let seconds: Int?
        let age_ms: Int64?
        let stale: Bool?

        private enum CodingKeys: String, CodingKey {
            case status, transient, header, seconds, age_ms, stale
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = try c.decodeIfPresent(Int.self, forKey: .status)
            transient = try c.decodeIfPresent(Bool.self, forKey: .transient)
            age_ms = try c.decodeIfPresent(Int64.self, forKey: .age_ms)
            stale = try c.decodeIfPresent(Bool.self, forKey: .stale)

            // Plain statements, not a `&&` inside a ternary: `decodeNil` throws, and Swift will not
            // let a throwing call sit inside a short-circuit operand.
            headerPresent = c.contains(.header)
            let headerIsNull = headerPresent ? try c.decodeNil(forKey: .header) : true
            header = headerIsNull ? nil : try c.decode(String.self, forKey: .header)

            secondsPresent = c.contains(.seconds)
            let secondsIsNull = secondsPresent ? try c.decodeNil(forKey: .seconds) : true
            seconds = secondsIsNull ? nil : try c.decode(Int.self, forKey: .seconds)
        }
    }

    private struct Resilience: Decodable {
        let contract: String
        let horizon_ms: Int64?
        let cases: [Case]
    }

    private struct Fixture: Decodable {
        let id: String
        let category: String
        let platforms: [String]
        let resilience: Resilience
    }

    func testResilienceFixtures() throws {
        let fixtures = try loadResilienceFixtures()
        XCTAssertFalse(fixtures.isEmpty, "No resilience fixtures found — the category must not silently vanish")

        var seenContracts = Set<String>()

        for f in fixtures {
            seenContracts.insert(f.resilience.contract)

            switch f.resilience.contract {
            case "transient_status":
                for c in f.resilience.cases {
                    guard let status = c.status, let expected = c.transient else {
                        return XCTFail("[\(f.id)] transient_status case needs `status` and `transient`")
                    }
                    XCTAssertEqual(
                        APIClient.transientStatusCodes.contains(status), expected,
                        "[\(f.id)] HTTP \(status) transient?"
                    )
                }

            case "retry_after":
                for c in f.resilience.cases {
                    guard c.headerPresent, c.secondsPresent else {
                        return XCTFail("[\(f.id)] retry_after case must state both `header` and `seconds` (null is a value, not an omission)")
                    }
                    let actual = APIClient.parseRetryAfter(c.header)
                    let label = "[\(f.id)] Retry-After \(c.header.map { "\"\($0)\"" } ?? "(absent)")"
                    if let expected = c.seconds {
                        XCTAssertEqual(actual, TimeInterval(expected), label)
                    } else {
                        XCTAssertNil(actual, "\(label) must be refused")
                    }
                }

            case "stale_horizon":
                guard let horizon = f.resilience.horizon_ms else {
                    return XCTFail("[\(f.id)] stale_horizon needs `horizon_ms`")
                }
                // A fixed `now` keeps the table exact: age is what varies, not the wall clock.
                let now: Int64 = 1_800_000_000_000
                for c in f.resilience.cases {
                    guard let ageMs = c.age_ms, let expected = c.stale else {
                        return XCTFail("[\(f.id)] stale_horizon case needs `age_ms` and `stale`")
                    }
                    XCTAssertEqual(
                        EventStore.isStale(tsMs: now - ageMs, nowMs: now, horizonMs: horizon), expected,
                        "[\(f.id)] age \(ageMs)ms stale?"
                    )
                }

            default:
                XCTFail("[\(f.id)] unknown resilience contract '\(f.resilience.contract)' — this runner must assert it, never skip it")
            }
        }

        // Every contract the schema defines must actually be exercised, or a fixture could be deleted
        // and this suite would still go green on the survivors.
        XCTAssertEqual(
            seenContracts, ["transient_status", "retry_after", "stale_horizon"],
            "every resilience contract must be covered by a fixture"
        )
    }

    private func loadResilienceFixtures() throws -> [Fixture] {
        guard let root = SharedFixtureTests.fixturesRootURL()?.appendingPathComponent("resilience") else {
            XCTFail("Could not locate packages/sdk-shared-fixtures/resilience")
            return []
        }
        let urls = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".fixture.json") }
            .sorted { $0.path < $1.path }

        let decoder = JSONDecoder()
        return try urls.compactMap { url in
            let f = try decoder.decode(Fixture.self, from: Data(contentsOf: url))
            guard f.category == "resilience", f.platforms.contains("ios") else { return nil }
            return f
        }
    }
}
