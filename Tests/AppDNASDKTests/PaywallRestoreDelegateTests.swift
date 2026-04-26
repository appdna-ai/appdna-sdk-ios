import XCTest
@testable import AppDNASDK

/// Compile-time + minimal-behavior tests for the 3 restore lifecycle methods
/// added to `AppDNAPaywallDelegate`. The actual delegate dispatch path is
/// verified end-to-end via the Mac build bridge with a sample app.
final class PaywallRestoreDelegateTests: XCTestCase {

    // MARK: - Backward compatibility

    /// Pre-spec host apps that conform to AppDNAPaywallDelegate WITHOUT implementing
    /// the 3 new restore methods must still compile, thanks to the default empty
    /// implementations in the protocol extension. This test would fail to build
    /// (not just fail at runtime) if the defaults were missing.
    func testProtocolBackwardCompatible() {
        final class MinimalLegacyDelegate: AppDNAPaywallDelegate {}
        let delegate = MinimalLegacyDelegate()

        // Default empty methods are no-ops — these calls must succeed silently.
        delegate.onPaywallRestoreStarted(paywallId: "p1")
        delegate.onPaywallRestoreCompleted(paywallId: "p1", productIds: [])
        delegate.onPaywallRestoreFailed(paywallId: "p1", error: TestError.expected)
        XCTAssertTrue(true, "Default empty implementations exist — host apps don't need to override.")
    }

    // MARK: - Method invocation

    /// A delegate that records every restore-lifecycle call. Hosts will use this
    /// pattern to wire restore UI (toast / alert / spinner) to the paywall.
    func testRestoreCallbackRecording() {
        final class RecorderDelegate: AppDNAPaywallDelegate {
            var startedCount = 0
            var completed: [(paywallId: String, productIds: [String])] = []
            var failed: [(paywallId: String, error: Error)] = []

            func onPaywallRestoreStarted(paywallId: String) {
                startedCount += 1
            }
            func onPaywallRestoreCompleted(paywallId: String, productIds: [String]) {
                completed.append((paywallId, productIds))
            }
            func onPaywallRestoreFailed(paywallId: String, error: Error) {
                failed.append((paywallId, error))
            }
        }

        let recorder = RecorderDelegate()

        // Simulated invocations — same shapes the SDK fires from PaywallManager.handleRestore.
        recorder.onPaywallRestoreStarted(paywallId: "annual_promo")
        recorder.onPaywallRestoreCompleted(
            paywallId: "annual_promo",
            productIds: ["com.app.annual", "com.app.monthly"],
        )
        recorder.onPaywallRestoreFailed(
            paywallId: "another_paywall",
            error: TestError.expected,
        )

        XCTAssertEqual(recorder.startedCount, 1)
        XCTAssertEqual(recorder.completed.count, 1)
        XCTAssertEqual(recorder.completed[0].paywallId, "annual_promo")
        XCTAssertEqual(recorder.completed[0].productIds, ["com.app.annual", "com.app.monthly"])
        XCTAssertEqual(recorder.failed.count, 1)
        XCTAssertEqual(recorder.failed[0].paywallId, "another_paywall")
    }

    // MARK: - Helpers

    private enum TestError: Error {
        case expected
    }
}
