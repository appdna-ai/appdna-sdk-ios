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
            delegate?.onPaywallPurchaseFailed(paywallId: id, error: error)
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
                    delegate?.onPaywallDismissed(paywallId: id)
                }
            }
        )

        let hostingController = UIHostingController(rootView: paywallView)
        hostingController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        viewController.present(hostingController, animated: true) {
            delegate?.onPaywallPresented(paywallId: id)
        }
    }

    // MARK: - Purchase flow

    private func handlePurchase(paywallId: String, plan: PaywallPlan, delegate: AppDNAPaywallDelegate?) {
        guard let bridge = billingBridge else {
            Log.error("No billing bridge configured")
            return
        }

        delegate?.onPaywallPurchaseStarted(paywallId: paywallId, productId: plan.productId)
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
                    delegate?.onPaywallPurchaseCompleted(
                        paywallId: paywallId,
                        productId: result.productId,
                        transaction: TransactionInfo(
                            transactionId: result.transactionId,
                            productId: result.productId,
                            purchaseDate: Date()
                        )
                    )
                }
            } catch {
                eventTracker.track(event: "purchase_failed", properties: [
                    "paywall_id": paywallId,
                    "product_id": plan.productId,
                    "error": error.localizedDescription,
                ])
                DispatchQueue.main.async {
                    delegate?.onPaywallPurchaseFailed(
                        paywallId: paywallId,
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
                    // Restore results are handled via the billing delegate
                    Log.info("Restore completed for paywall \(paywallId) with \(restored.count) products")
                }
            } catch {
                Log.error("Restore failed: \(error.localizedDescription)")
            }
        }
    }
}
