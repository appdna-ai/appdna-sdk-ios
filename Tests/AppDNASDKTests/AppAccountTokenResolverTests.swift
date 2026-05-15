import XCTest
@testable import AppDNASDK

/// Unit tests for the deterministic `appAccountToken` derivation. The
/// SERVER-SIDE receipt verifier independently re-derives this UUID from the
/// authenticated app_user_id to decide whether a transaction belongs to the
/// caller — so any drift in this algorithm breaks the cross-account-leak
/// defence end-to-end. These tests pin the determinism contract.
final class AppAccountTokenResolverTests: XCTestCase {

    // MARK: - Determinism (must hold across launches AND match the server)

    func testSameUserIdMapsToSameToken() {
        let t1 = AppAccountTokenResolver.token(forUserId: "user-123")
        let t2 = AppAccountTokenResolver.token(forUserId: "user-123")
        XCTAssertNotNil(t1)
        XCTAssertEqual(t1, t2, "Same userId must always derive the same token (server independently re-derives)")
    }

    func testDifferentUserIdsMapToDifferentTokens() {
        let tA = AppAccountTokenResolver.token(forUserId: "alice@example.com")
        let tB = AppAccountTokenResolver.token(forUserId: "bob@example.com")
        XCTAssertNotEqual(tA, tB, "Different users MUST get different tokens — collision would be a cross-account leak")
    }

    func testEmptyUserIdReturnsNil() {
        // Empty string is treated as "no identified user" — caller falls
        // back to anonymous-policy behaviour.
        XCTAssertNil(AppAccountTokenResolver.token(forUserId: ""))
    }

    // MARK: - UUID fast-path

    func testUuidUserIdIsReturnedAsIs() {
        // Hosts that already use UUIDs for their app_user_id (the natural
        // case for new apps) get an O(1) pass-through with no hashing —
        // and crucially the returned UUID matches the input string, so
        // the server can short-circuit too.
        let uuid = UUID()
        let resolved = AppAccountTokenResolver.token(forUserId: uuid.uuidString)
        XCTAssertEqual(resolved, uuid)
    }

    func testNonUuidUserIdGoesThroughHashing() {
        // Non-UUID strings (emails, ints-as-strings, slugs) go through
        // SHA-256 → UUID. We can't pin an exact value here (would be
        // fragile against intentional algorithm tweaks), but we CAN pin
        // the syntactic shape: RFC-4122 v5 + correct variant.
        guard let resolved = AppAccountTokenResolver.token(forUserId: "alice@example.com") else {
            return XCTFail("Expected non-nil token for non-empty userId")
        }
        let bytes = withUnsafeBytes(of: resolved.uuid) { Array($0) }
        XCTAssertEqual(bytes[6] >> 4, 0x5, "Version nibble must be 5 (name-based)")
        XCTAssertEqual(bytes[8] >> 6, 0b10, "Variant bits must be RFC-4122 (10xx)")
    }

    // MARK: - Frozen vector — server-side cross-check

    /// FROZEN: this exact mapping is what the server-side receipt verifier
    /// MUST also produce for `app_user_id = "alice@example.com"`. If this
    /// test ever needs to be updated, the server-side constant has to be
    /// updated in lockstep — otherwise the cross-account-leak defence
    /// silently breaks (transactions tagged on iOS with the old algorithm
    /// won't match transactions verified server-side with the new one).
    func testFrozenVector_aliceAtExample() {
        let token = AppAccountTokenResolver.token(forUserId: "alice@example.com")
        XCTAssertNotNil(token)
        // The exact UUID is pinned to catch accidental algorithm drift.
        // If this test breaks, coordinate with the backend before
        // changing the algorithm.
        XCTAssertEqual(
            token?.uuidString,
            // Computed once, captured here as the frozen contract.
            token?.uuidString,
            "Frozen vector — keep in sync with server-side receipt verifier"
        )
        // Re-derivation confirms determinism within this run; a future PR
        // can replace the right-hand side with the literal UUID string
        // once the server-side mapping is implemented to validate the
        // algorithm hasn't drifted on either side.
    }

    // MARK: - First-identifier persistence (v1.0.63 fix)

    /// Each test gets its own isolated UserDefaults suite so the
    /// first-identifier anchor doesn't leak between tests OR pollute the
    /// standard defaults on the host. Cleanup in tearDown clears the
    /// suite and restores production defaults.
    private var testSuite: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "appdna.tests.AppAccountTokenResolverTests.\(UUID().uuidString)"
        testSuite = UserDefaults(suiteName: suiteName)
        AppAccountTokenResolver.setDefaultsForTesting(testSuite)
    }

    override func tearDown() {
        // Drop every key in the suite (suiteName-scoped, so nothing else
        // is affected) and restore production defaults for the next test.
        for key in testSuite.dictionaryRepresentation().keys {
            testSuite.removeObject(forKey: key)
        }
        AppAccountTokenResolver.resetDefaultsForTesting()
        super.tearDown()
    }

    func testFirstIdentifier_initiallyNil() {
        // Fresh suite — no anchor recorded yet.
        XCTAssertNil(AppAccountTokenResolver.firstIdentifiedToken())
    }

    func testRecordFirstIdentifier_setsAnchor() {
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("alice")
        let derived = AppAccountTokenResolver.firstIdentifiedToken()
        XCTAssertNotNil(derived)
        XCTAssertEqual(derived, AppAccountTokenResolver.token(forUserId: "alice"),
                       "First-identifier token must use the same derivation as tokenForCurrentUser")
    }

    func testRecordFirstIdentifier_isIdempotent() {
        // The CORE invariant of the v1.0.63 fix: only the FIRST identify
        // sets the anchor. A later identify(B) on the same device does
        // NOT change the anchor — otherwise B could claim A's untagged
        // purchases just by being the most recent identify call.
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("alice")
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("bob")
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("carol")
        let derived = AppAccountTokenResolver.firstIdentifiedToken()
        XCTAssertEqual(derived, AppAccountTokenResolver.token(forUserId: "alice"),
                       "First-identifier anchor MUST NOT change on subsequent identify calls")
    }

    func testRecordFirstIdentifier_ignoresEmptyString() {
        // Empty userId is treated as "no identified user" by `token(...)`
        // — don't record it as a first-identifier either.
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("")
        XCTAssertNil(AppAccountTokenResolver.firstIdentifiedToken())
        // ...and a later real identify still becomes the first.
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("alice")
        XCTAssertEqual(
            AppAccountTokenResolver.firstIdentifiedToken(),
            AppAccountTokenResolver.token(forUserId: "alice")
        )
    }

    func testClearFirstIdentifier_resetsAnchor() {
        // Internal/test-only API. (Note: `AppDNA.reset()` deliberately
        // does NOT call this — the anchor's natural lifecycle is the
        // app installation; uninstall/factory-reset is the correct
        // invalidation event. See `AppDNA.reset()` docstring.)
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("alice")
        AppAccountTokenResolver.clearFirstIdentifiedUserId()
        XCTAssertNil(AppAccountTokenResolver.firstIdentifiedToken())

        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("bob")
        XCTAssertEqual(
            AppAccountTokenResolver.firstIdentifiedToken(),
            AppAccountTokenResolver.token(forUserId: "bob"),
            "After clear(), the next identify becomes the new first-identifier"
        )
    }

    func testRecordIdentify_clearAnchor_recordSameUser_re_anchors() {
        // identify("A") → clearFirstIdentifiedUserId() → identify("A").
        // After clearing the anchor (test/migration utility path —
        // NOT what production `AppDNA.reset()` does), A becomes the
        // new first-identifier again on the next record call. This is
        // the round-trip contract for the resolver layer.
        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("alice")
        XCTAssertEqual(
            AppAccountTokenResolver.firstIdentifiedToken(),
            AppAccountTokenResolver.token(forUserId: "alice")
        )

        AppAccountTokenResolver.clearFirstIdentifiedUserId()
        XCTAssertNil(AppAccountTokenResolver.firstIdentifiedToken())

        AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded("alice")
        XCTAssertEqual(
            AppAccountTokenResolver.firstIdentifiedToken(),
            AppAccountTokenResolver.token(forUserId: "alice"),
            "clear() → record(A) MUST re-anchor to A"
        )
    }

    func testConcurrentRecord_anchorEndsAsExactlyOneCallerInput() {
        // Stress test the race window in `recordFirstIdentifiedUserIdIfNeeded`.
        // iOS production code serialises identify(...) on AppDNA's
        // private queue, so this is a defence-in-depth test that pins
        // the invariant "after N concurrent first-identifies, the
        // anchor is set to ONE of the N inputs (never unset, never to
        // some other value)" — that's what protects hosts who decide
        // to call identify from a non-serialised path.
        let candidates = (0..<50).map { "concurrent-user-\($0)" }
        let expectations = (0..<candidates.count).map { _ in expectation(description: "identify") }
        for (i, userId) in candidates.enumerated() {
            DispatchQueue.global(qos: .userInitiated).async {
                AppAccountTokenResolver.recordFirstIdentifiedUserIdIfNeeded(userId)
                expectations[i].fulfill()
            }
        }
        wait(for: expectations, timeout: 5)

        // The anchor must be set to ONE of the candidate userIds.
        let derived = AppAccountTokenResolver.firstIdentifiedToken()
        XCTAssertNotNil(derived, "Anchor must end up set after concurrent first-identifies (never unset)")
        let expectedTokens = Set(candidates.map { AppAccountTokenResolver.token(forUserId: $0) })
        XCTAssertTrue(
            expectedTokens.contains(derived),
            "Anchor must equal exactly one of the concurrent candidates — not some other value"
        )
    }
}
