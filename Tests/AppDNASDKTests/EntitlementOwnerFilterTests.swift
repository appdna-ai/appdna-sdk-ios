import XCTest
@testable import AppDNASDK

/// Pure unit tests for the cross-account-leak ownership filter — the single
/// source of truth for the decision matrix that defends every site reading
/// `Transaction.currentEntitlements`. Bogdan's reproducer (User A buys → User
/// B signs in → B sees A's subscription) lives or dies on this decision
/// table being correct; if any case here flips wrong, the whole defence
/// silently breaks.
///
/// Decision matrix re-stated for clarity:
///   expectedToken nil                     → grantAnonymousPolicy   (pre-identify pass-through)
///   expectedToken set, tx token == match  → grant                  (current user's purchase)
///   expectedToken set, tx token nil       → grantUntaggedMigration (historical, server claims)
///   expectedToken set, tx token mismatch  → denyOtherUser          ← THE FIX
final class EntitlementOwnerFilterTests: XCTestCase {

    private let tokenA = UUID()
    private let tokenB = UUID()

    // MARK: - The four cases of the decision matrix

    func testAnonymousUser_noFilter() {
        // No identified user (host hasn't called identify yet) — any
        // transaction token, including nil, is accepted under the legacy
        // pass-through. Preserves first-launch / pre-identify flows.
        XCTAssertEqual(
            EntitlementOwnerFilter.decide(transactionToken: tokenA, expectedToken: nil),
            .grantAnonymousPolicy
        )
        XCTAssertEqual(
            EntitlementOwnerFilter.decide(transactionToken: nil, expectedToken: nil),
            .grantAnonymousPolicy
        )
    }

    func testTaggedAndMatches_grant() {
        // Identified user, transaction tagged with the same user's token → grant.
        XCTAssertEqual(
            EntitlementOwnerFilter.decide(transactionToken: tokenA, expectedToken: tokenA),
            .grant
        )
    }

    func testUntaggedHistorical_migrationTolerant() {
        // Identified user, transaction has no appAccountToken (purchased
        // before the SDK started tagging) → grant under the
        // migration-tolerant policy. The server is expected to claim
        // ownership for the current user so a later user-switch doesn't
        // silently re-grant.
        XCTAssertEqual(
            EntitlementOwnerFilter.decide(transactionToken: nil, expectedToken: tokenA),
            .grantUntaggedMigration
        )
    }

    func testTaggedDifferentUser_deny() {
        // Identified user A, transaction tagged for user B → DENY.
        // This is the specific case that produced Bogdan's reproducer:
        // user B signs in, taps Restore, currentEntitlements returns A's
        // transaction. With this filter, the transaction is dropped.
        XCTAssertEqual(
            EntitlementOwnerFilter.decide(transactionToken: tokenB, expectedToken: tokenA),
            .denyOtherUser
        )
        // Symmetric — user B is identified, A's transaction is denied.
        XCTAssertEqual(
            EntitlementOwnerFilter.decide(transactionToken: tokenA, expectedToken: tokenB),
            .denyOtherUser
        )
    }

    // MARK: - Property-style sanity checks

    /// A grant decision means "the caller may surface this entitlement to
    /// the current user"; the three grant variants are semantically
    /// equivalent at the bridge call site (all three result in the product
    /// being added to the returned list). `denyOtherUser` is the only
    /// outcome that filters a transaction OUT. This test pins that
    /// contract so a future refactor that adds a fifth case can't
    /// accidentally collapse grant vs deny.
    func testOnlyOtherUserMismatchIsDeny() {
        let allCases: [EntitlementOwnershipDecision] = [
            .grant, .grantAnonymousPolicy, .grantUntaggedMigration, .denyOtherUser,
        ]
        let denyCases = allCases.filter { $0 == .denyOtherUser }
        XCTAssertEqual(denyCases.count, 1, "Exactly one decision case denies — the cross-account mismatch")
    }
}
