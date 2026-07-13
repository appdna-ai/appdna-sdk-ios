import XCTest
import StoreKit
@testable import AppDNASDK

/// The billing failure surface handed to hosts used to be a bare `Error`: a wrapper (RN/Flutter) or a
/// host could read `localizedDescription` and nothing else, so "user cancelled" was indistinguishable
/// from "card declined". These tests pin the stable discriminator.
final class BillingErrorTypeTests: XCTestCase {

    func testBillingErrorCarriesStableDiscriminator() {
        XCTAssertEqual(BillingError.productNotFound("p1").errorType, "productNotFound")
        XCTAssertEqual(BillingError.verificationFailed.errorType, "verificationFailed")
        XCTAssertEqual(BillingError.networkError(URLError(.timedOut)).errorType, "networkError")
        XCTAssertEqual(BillingError.serverError("boom").errorType, "serverError")
        XCTAssertEqual(BillingError.providerNotAvailable("nope").errorType, "providerNotAvailable")
        XCTAssertEqual(BillingError.userCancelled.errorType, "userCancelled")
    }

    /// The ACTIVE purchase path throws `StoreKit2Error`, not `BillingError` — the mapper has to cover
    /// it or every real-world cancel would report as "unknown".
    func testStoreKit2ErrorsMapToTheSameVocabulary() {
        XCTAssertEqual(billingErrorType(StoreKit2Error.userCancelled), "userCancelled")
        XCTAssertEqual(billingErrorType(StoreKit2Error.productNotFound("p1")), "productNotFound")
        XCTAssertEqual(billingErrorType(StoreKit2Error.verificationFailed), "verificationFailed")
        // "pending", NOT "purchasePending". Android's `billingErrorType` has always returned "pending"
        // for the same condition, so `onPaywallPurchaseFailed(errorType:)` — and every wrapper that
        // forwards it — forked per platform in the ONE vocabulary that exists so it cannot.
        XCTAssertEqual(billingErrorType(StoreKit2Error.purchasePending), "pending")
        XCTAssertEqual(billingErrorType(StoreKit2Error.unknown), "unknown")
    }

    /// The vocabulary is a CLOSED set, and it is the contract two wrappers reject promises with. Pin
    /// it whole: a new discriminator that only one platform knows is a `switch` a host cannot write.
    func testDiscriminatorVocabularyIsTheOneBothPlatformsShare() {
        let vocabulary: Set<String> = [
            "userCancelled", "pending", "productNotFound", "verificationFailed",
            "networkError", "serverError", "providerNotAvailable", "unknown",
        ]
        let produced: Set<String> = [
            billingErrorType(StoreKit2Error.userCancelled),
            billingErrorType(StoreKit2Error.purchasePending),
            billingErrorType(StoreKit2Error.productNotFound("p")),
            billingErrorType(StoreKit2Error.verificationFailed),
            billingErrorType(BillingError.networkError(URLError(.timedOut))),
            billingErrorType(BillingError.serverError("500")),
            billingErrorType(BillingError.providerNotAvailable("no")),
            billingErrorType(StoreKit2Error.unknown),
        ]
        XCTAssertEqual(produced, vocabulary)
    }

    func testBillingErrorsMapThroughTheTopLevelMapper() {
        XCTAssertEqual(billingErrorType(BillingError.userCancelled), "userCancelled")
        XCTAssertEqual(billingErrorType(BillingError.serverError("500")), "serverError")
    }

    func testTransportFailureIsNetworkError() {
        XCTAssertEqual(billingErrorType(URLError(.notConnectedToInternet)), "networkError")
    }

    /// An error we don't recognize must NOT be force-fit into a category the host would act on.
    func testUnrecognizedErrorIsUnknown() {
        let err = NSError(domain: "ai.appdna.sdk", code: 404, userInfo: nil)
        XCTAssertEqual(billingErrorType(err), "unknown")
    }

    // MARK: - Source compatibility

    /// Existing hosts implement ONLY `onPaywallPurchaseFailed(paywallId:error:)`. The SDK now calls
    /// the three-argument variant; the protocol extension must forward so those hosts keep receiving
    /// the callback.
    func testLegacyDelegateStillReceivesFailureFromTypedCall() {
        let host = LegacyOnlyPaywallDelegate()
        let delegate: AppDNAPaywallDelegate = host

        delegate.onPaywallPurchaseFailed(
            paywallId: "pw_1",
            error: BillingError.userCancelled,
            errorType: "userCancelled"
        )

        XCTAssertEqual(host.failures, ["pw_1"])
    }

    /// A host that DOES implement the typed method receives the discriminator.
    func testTypedDelegateReceivesErrorType() {
        let host = TypedPaywallDelegate()
        let delegate: AppDNAPaywallDelegate = host

        delegate.onPaywallPurchaseFailed(
            paywallId: "pw_1",
            error: BillingError.userCancelled,
            errorType: billingErrorType(BillingError.userCancelled)
        )

        XCTAssertEqual(host.errorTypes, ["userCancelled"])
    }
}

private final class LegacyOnlyPaywallDelegate: AppDNAPaywallDelegate {
    var failures: [String] = []
    func onPaywallPurchaseFailed(paywallId: String, error: Error) {
        failures.append(paywallId)
    }
}

private final class TypedPaywallDelegate: AppDNAPaywallDelegate {
    var errorTypes: [String] = []
    func onPaywallPurchaseFailed(paywallId: String, error: Error, errorType: String) {
        errorTypes.append(errorType)
    }
}
