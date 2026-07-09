import Foundation

/// SPEC-070-B PN row 14 (AC-36 / W8) — the persisted analytics-consent decision.
///
/// Consent used to live only in `EventTracker.analyticsConsent`, an in-memory `Bool` initialised to
/// `true`. So `setConsent(false)` held for the life of the process and was silently undone by the
/// next cold start: an opted-out user was opted back in on every launch. That is a bug, not a
/// missing feature, which is why the fix lands here rather than waiting for the full multi-purpose
/// consent store (SPEC-424).
///
/// `UserDefaults` — not the EventStore — because the decision must be readable *before*
/// `configure()` wires the pipeline, exactly like `ClientSeqCounter`.
///
/// Three states, and the third is load-bearing:
///   - `true`  — granted
///   - `false` — denied
///   - `nil`   — **no decision yet**. `AppDNAOptions.requireConsent` decides what that means.
internal enum ConsentStore {
    private static let key = "ai.appdna.sdk.analytics_consent"

    /// The persisted decision, or nil if the user has never been asked.
    static var decision: Bool? {
        get { UserDefaults.standard.object(forKey: key) as? Bool }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Resolve the decision that `configure()` should start with.
    /// - Parameter requireConsent: when true, the absence of a decision means **denied** (opt-in).
    static func effectiveConsent(requireConsent: Bool) -> Bool {
        decision ?? !requireConsent
    }

    /// Test seam. Not part of the public surface.
    static func reset() { decision = nil }
}
