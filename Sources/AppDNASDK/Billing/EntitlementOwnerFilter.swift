import Foundation

/// Outcome of a per-transaction ownership check against the currently
/// identified user. Returned from `EntitlementOwnerFilter.decide(...)`.
enum EntitlementOwnershipDecision: Equatable {
    /// Transaction is bound to the current user — grant.
    case grant
    /// Transaction belongs to a different user — DENY (cross-account leak guard).
    case denyOtherUser
    /// Untagged historical transaction — grant under the migration-tolerant
    /// policy (§ "migration-tolerant"). The caller is expected to surface this
    /// to the server-side receipt-verifier so the backend can claim ownership
    /// for the current user and prevent silent re-grant on a later user switch.
    case grantUntaggedMigration
    /// No identified user — fall back to no ownership filter (pre-`identify`
    /// flows like first-launch "Restore" before any user is established).
    case grantAnonymousPolicy
}

/// Pure, fully-unit-testable ownership filter used by every site that reads
/// `Transaction.currentEntitlements`. The decision matrix below is the single
/// source of truth for the SDK's cross-account-entitlement-leak defence.
///
/// Decision matrix:
/// ```
///   expectedToken  | tx.appAccountToken | decision
///   ───────────────┼────────────────────┼──────────────────────────
///   nil            | any                | grantAnonymousPolicy
///   set            | == expectedToken   | grant
///   set            | nil                | grantUntaggedMigration
///   set            | != expectedToken   | denyOtherUser
/// ```
///
/// The "anonymous" branch preserves pre-identify behaviour (a host that calls
/// `restorePurchases` before any user has identified gets every transaction
/// the device knows about — same as before this fix). Once the host calls
/// `AppDNA.identify(...)`, the filter is armed and the per-user binding is
/// enforced on every subsequent read.
///
/// Server-side enforcement (`receiptVerifier.restore/verify` — see
/// `ReceiptVerifier.swift`) is the PRIMARY defence; this client-side filter
/// is a belt-and-suspenders layer for the cached/silent paths
/// (`refreshEntitlementCache` and the bridge's `getEntitlements`/`restore`
/// shortcuts that don't always round-trip the verifier).
enum EntitlementOwnerFilter {

    /// Apply the decision matrix above to a single transaction's token.
    static func decide(
        transactionToken: UUID?,
        expectedToken: UUID?
    ) -> EntitlementOwnershipDecision {
        guard let expected = expectedToken else { return .grantAnonymousPolicy }
        if transactionToken == expected { return .grant }
        if transactionToken == nil { return .grantUntaggedMigration }
        return .denyOtherUser
    }
}
