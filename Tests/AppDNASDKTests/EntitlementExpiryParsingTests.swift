import XCTest
@testable import AppDNASDK

/// 🔴 EVERY `expiresAt` THE SERVER SENT PARSED TO `nil`.
///
/// The server serialises expiry with `Date.toISOString()` — `2026-07-14T10:00:00.000Z`, WITH fractional
/// seconds (`EntitlementSyncService.ts`: `sub.current_period_end?.toISOString()`). The SDK parsed it
/// with a bare `ISO8601DateFormatter()`, whose default `formatOptions` do NOT include
/// `.withFractionalSeconds` — and without that flag, parsing a fractional timestamp returns nil.
///
/// Not intermittently. Every entitlement, every time, on every build.
///
/// So a host asking "when does this subscription lapse?" — to show a renewal date, to warn before
/// expiry, to decide whether to re-verify — got nil. Combined with `BillingModule.getEntitlements()`,
/// which cannot supply an expiry at all (the bridge protocol returns product IDs only), that made
/// `Entitlement.expiresAt` a public property of a public type that could not hold a value.
///
/// This is exactly the class of bug that hides forever: `flatMap` on a failed parse yields nil, which is
/// indistinguishable from "the server did not send one". No error, no log, no crash. It just silently
/// means the wrong thing.
final class EntitlementExpiryParsingTests: XCTestCase {

    /// THE ONE THAT WAS BROKEN: what our server actually puts on the wire.
    func testTheFractionalSecondFormatOurServerSendsIsParsed() {
        let parsed = ISO8601.date(from: "2026-07-14T10:00:00.000Z")

        guard let parsed else {
            return XCTFail(
                "the SDK cannot parse the ONLY expiry format our server sends (`Date.toISOString()`), " +
                "so every entitlement's expiresAt silently came back nil"
            )
        }
        // 2026-07-14T10:00:00Z
        XCTAssertEqual(
            parsed.timeIntervalSince1970,
            1_784_023_200,
            accuracy: 1,
            "parsed to the wrong instant"
        )
    }

    /// ...and the format without fractional seconds must keep working — a store, or a hand-written
    /// fixture, may send it. Switching the formatter to `.withFractionalSeconds` ALONE would have broken
    /// this one, trading a silent nil for a different silent nil.
    func testThePlainSecondFormatStillParses() {
        XCTAssertNotNil(
            ISO8601.date(from: "2026-07-14T10:00:00Z"),
            "a non-fractional ISO8601 timestamp stopped parsing — the fix broke the other spelling"
        )
    }

    /// Garbage stays nil. `expiresAt` is legitimately optional (ADR-002 N11: a platform that does not
    /// know must say so rather than fabricate), so the parser must not start inventing dates either.
    func testGarbageIsStillNil() {
        XCTAssertNil(ISO8601.date(from: ""))
        XCTAssertNil(ISO8601.date(from: "not a date"))
        XCTAssertNil(ISO8601.date(from: "14/07/2026"))
    }
}
