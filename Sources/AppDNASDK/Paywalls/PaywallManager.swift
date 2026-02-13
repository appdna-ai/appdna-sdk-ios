import Foundation
import UIKit
import SwiftUI

/// Manages paywall presentation, purchase flow, and event tracking.
final class PaywallManager {
    private let remoteConfigManager: RemoteConfigManager
    private let billingBridge: BillingBridgeProtocol?
    private let eventTracker: EventTracker

    init(
        remoteConfigManager: RemoteConfigManager,
        billingBridge: BillingBridgeProtocol?,
        eventTracker: EventTracker
    ) {
        self.remoteConfigManager = remoteConfigManager
        self.billingBridge = billingBridge
        self.eventTracker = eventTracker
    }

    /// Present a paywall modally. Must be called on main thread.
    func present(
        id: String,
        from viewController: UIViewController,
        context: PaywallContext?,
        delegate: AppDNAPaywallDelegate?
    ) {
        guard let config = remoteConfigManager.getPaywallConfig(id: id) else {
            Log.error("Paywall config not found for id: \(id)")
            let error = NSError(
                domain: "ai.appdna.sdk",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Paywall config not found"]
            )
            delegate?.paywallDidFailPurchase(paywallId: id, productId: "", error: error)
            return
        }

        // Track view event
        eventTracker.track(event: "paywall_view", properties: [
            "paywall_id": id,
            "placement": context?.placement ?? "unknown",
        ])

        let paywallView = PaywallRenderer(
            config: config,
            onPlanSelected: { [weak self] plan in
                self?.handlePurchase(paywallId: id, plan: plan, delegate: delegate)
            },
            onRestore: { [weak self] in
                self?.handleRestore(paywallId: id, delegate: delegate)
            },
            onDismiss: { [weak self] reason in
                self?.eventTracker.track(event: "paywall_close", properties: [
                    "paywall_id": id,
                    "dismiss_reason": reason.rawValue,
                ])
                viewController.dismiss(animated: true) {
                    delegate?.paywallDidDismiss(paywallId: id, reason: reason)
                }
            }
        )

        let hostingController = UIHostingController(rootView: paywallView)
        hostingController.modalPresentationStyle = .fullScreen
        viewController.present(hostingController, animated: true) {
            delegate?.paywallDidAppear(paywallId: id)
        }
    }

    // MARK: - Purchase flow

    private func handlePurchase(paywallId: String, plan: PaywallPlan, delegate: AppDNAPaywallDelegate?) {
        guard let bridge = billingBridge else {
            Log.error("No billing bridge configured")
            return
        }

        delegate?.paywallDidStartPurchase(paywallId: paywallId, productId: plan.productId)
        eventTracker.track(event: "purchase_started", properties: [
            "paywall_id": paywallId,
            "product_id": plan.productId,
        ])

        Task {
            do {
                let result = try await bridge.purchase(productId: plan.productId)
                eventTracker.track(event: "purchase_completed", properties: [
                    "paywall_id": paywallId,
                    "product_id": result.productId,
                    "price": result.price,
                    "currency": result.currency,
                    "provider": result.provider,
                ])
                DispatchQueue.main.async {
                    delegate?.paywallDidCompletePurchase(
                        paywallId: paywallId,
                        productId: result.productId,
                        transactionId: result.transactionId
                    )
                }
            } catch {
                eventTracker.track(event: "purchase_failed", properties: [
                    "paywall_id": paywallId,
                    "product_id": plan.productId,
                    "error": error.localizedDescription,
                ])
                DispatchQueue.main.async {
                    delegate?.paywallDidFailPurchase(
                        paywallId: paywallId,
                        productId: plan.productId,
                        error: error
                    )
                }
            }
        }
    }

    private func handleRestore(paywallId: String, delegate: AppDNAPaywallDelegate?) {
        guard let bridge = billingBridge else { return }

        Task {
            do {
                let restored = try await bridge.restore()
                eventTracker.track(event: "purchase_restored", properties: [
                    "paywall_id": paywallId,
                    "restored_count": restored.count,
                ])
                DispatchQueue.main.async {
                    delegate?.paywallDidRestorePurchases(paywallId: paywallId, restoredProductIds: restored)
                }
            } catch {
                Log.error("Restore failed: \(error.localizedDescription)")
            }
        }
    }
}
