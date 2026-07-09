import XCTest
@testable import AppDNASDK

/// Guards the transient-vs-permanent upload policy, `Retry-After` parsing, and
/// retry jitter.
///
/// Context: `sendEvents` latched `eventUploadPermanentlyFailed = true` for the
/// entire `400..<500` range. HTTP 429 lives in that range, so a single rate-limit
/// response — the expected behavior under load — paused every event upload until
/// the app restarted. Android retried it. Neither platform honored `Retry-After`,
/// and iOS applied no jitter, so a throttled fleet retried in lockstep.
final class RetryPolicyTests: XCTestCase {

    // MARK: - Transient status codes

    func testRateLimitAndTimeoutAreTransientNotPermanent() {
        XCTAssertTrue(APIClient.transientStatusCodes.contains(429), "429 must be retried, never latched permanent")
        XCTAssertTrue(APIClient.transientStatusCodes.contains(408), "408 must be retried")
    }

    func testGenuinelyPermanentCodesAreNotTransient() {
        for code in [400, 401, 403, 404, 422] {
            XCTAssertFalse(APIClient.transientStatusCodes.contains(code), "\(code) should stay permanent")
        }
    }

    // MARK: - Retry-After: delta-seconds

    func testParsesDeltaSeconds() {
        XCTAssertEqual(APIClient.parseRetryAfter("30"), 30)
    }

    func testTolerersSurroundingWhitespace() {
        XCTAssertEqual(APIClient.parseRetryAfter("  30  "), 30)
    }

    func testCapsExcessiveDelta() {
        // A hostile or mistaken header must not park the queue.
        XCTAssertEqual(APIClient.parseRetryAfter("99999"), APIClient.maxRetryAfter)
    }

    func testRejectsZeroNegativeAndUnparseable() {
        XCTAssertNil(APIClient.parseRetryAfter("0"))
        XCTAssertNil(APIClient.parseRetryAfter("-5"))
        XCTAssertNil(APIClient.parseRetryAfter("soon"))
        XCTAssertNil(APIClient.parseRetryAfter(""))
        XCTAssertNil(APIClient.parseRetryAfter(nil))
    }

    // MARK: - Retry-After: HTTP-date (RFC 9110 permits both forms)

    func testParsesFutureHTTPDate() {
        let parsed = APIClient.parseRetryAfter(Self.httpDate(secondsFromNow: 45))
        XCTAssertNotNil(parsed)
        XCTAssertTrue((1...60).contains(Int(parsed ?? 0)), "expected ~45s, got \(String(describing: parsed))")
    }

    func testRejectsPastHTTPDate() {
        XCTAssertNil(APIClient.parseRetryAfter(Self.httpDate(secondsFromNow: -60)))
    }

    func testCapsFarFutureHTTPDate() {
        XCTAssertEqual(APIClient.parseRetryAfter(Self.httpDate(secondsFromNow: 10 * 3600)), APIClient.maxRetryAfter)
    }

    // MARK: - Jitter (parity with Android's ±25%)

    func testJitterStaysWithinTwentyFivePercent() {
        for base in [1.0, 2.0, 4.0] as [TimeInterval] {
            for _ in 0..<500 {
                let d = EventQueue.jittered(base)
                XCTAssertGreaterThanOrEqual(d, base * 0.75, "jitter fell below -25% of \(base)")
                XCTAssertLessThanOrEqual(d, base * 1.25, "jitter exceeded +25% of \(base)")
            }
        }
    }

    func testJitterIsActuallyRandom() {
        // Without jitter every client retries on the identical wall clock and
        // stampedes the server again. A constant would silently pass the bounds
        // check above, so assert we see spread.
        let samples = Set((0..<200).map { _ in EventQueue.jittered(2.0) })
        XCTAssertGreaterThan(samples.count, 1, "jittered() returned a constant")
    }

    func testJitterNeverNegative() {
        for _ in 0..<200 {
            XCTAssertGreaterThanOrEqual(EventQueue.jittered(0.0), 0)
        }
    }

    // MARK: - Helpers

    private static func httpDate(secondsFromNow: TimeInterval) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.string(from: Date().addingTimeInterval(secondsFromNow))
    }
}
