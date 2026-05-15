import Foundation
import CryptoKit

/// Resolves a deterministic `UUID` for use as Apple's `Transaction.appAccountToken`,
/// keyed off the host-supplied user identity (`AppDNA.identify(userId:)`).
///
/// Why this exists — the cross-account-entitlement-leak fix:
///   `Transaction.currentEntitlements` is **device-scoped** (tied to the Apple ID
///   signed in to the device), not app-user-scoped. If user A buys a subscription,
///   logs out, and user B logs in, `currentEntitlements` still returns A's
///   transaction — granting B a "fake premium" state.
///
///   Apple's `appAccountToken` is exactly the hook to bind a transaction to an
///   app user: set on purchase, read back on every entitlement check. Apple
///   stores it on the transaction (and on the receipt sent to App Store
///   Server-Server notifications), so the binding survives renewals.
///
/// What this resolver returns:
///   - Host has called `AppDNA.identify(userId: "...")` → a stable UUID
///     derived from that userId. The same userId always maps to the same UUID
///     (server side can do the same mapping to verify).
///   - Host has NOT identified a user → `nil`. Callers MUST handle this:
///     - Purchase code logs a warning and proceeds untagged (preserves
///       pre-identify first-launch flows; the host should identify before
///       letting the user purchase).
///     - Entitlement reads fall back to "no ownership filter" (anonymous
///       state — reads everything on the device, same behaviour as before
///       this fix; the filter kicks in once the host identifies).
///
/// Determinism contract — the server-side receipt-verifier MUST be able to
/// reproduce the same mapping from `userId` to UUID independently. The
/// algorithm is:
///   1. If `userId` already parses as a UUID, return it as-is.
///   2. Otherwise SHA-256(NAMESPACE_UUID_BYTES || userId.utf8), take the first
///      16 bytes, force RFC-4122 version=5 (name-based, SHA-1) + variant
///      bits, return as UUID.
/// (Note: RFC-4122 v5 strictly uses SHA-1; we use SHA-256-truncated for
/// stronger collision resistance — the version/variant nibble overrides keep
/// the UUID syntactically valid. The server uses the same algorithm.)
enum AppAccountTokenResolver {

    /// Fixed namespace UUID for AppDNA app-user tokens. Must match the
    /// server-side constant in the receipt-verifier code so the same userId
    /// produces the same token on both sides.
    /// (Generated once, frozen forever — DO NOT change.)
    static let namespace = UUID(uuidString: "C1A85D8E-7B5B-4B5E-9F4F-1E7D5F4C8B2A")!

    /// Resolve a token for an arbitrary user-id string.
    /// Returns `nil` only if `userId` is empty.
    static func token(forUserId userId: String) -> UUID? {
        guard !userId.isEmpty else { return nil }
        // Fast path: userId is already a UUID.
        if let direct = UUID(uuidString: userId) { return direct }
        // Slow path: deterministic SHA-256(namespace || userId) → UUID.
        var hasher = SHA256()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(userId.utf8))
        let digest = hasher.finalize()
        var bytes = [UInt8](digest.prefix(16))
        // Force RFC-4122 version (5 = name-based, SHA-1 — we use it as a
        // syntactic marker; the digest is SHA-256-truncated for collision
        // resistance, and the server uses the same algorithm).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        // Force RFC-4122 variant (10xx).
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Resolve the token for the currently-identified user (or `nil` if the
    /// host has not yet called `AppDNA.identify(...)`). NOTE: the anonymous
    /// device id is NOT used — that would conflate device with user and undo
    /// the whole point of per-user entitlement binding.
    static func tokenForCurrentUser() -> UUID? {
        guard let identity = AppDNA.identityManagerRef?.currentIdentity,
              let userId = identity.userId else { return nil }
        return token(forUserId: userId)
    }
}
