import Foundation
import UIKit
import SwiftUI

extension Notification.Name {
    static let paywallPurchaseSuccess = Notification.Name("ai.appdna.paywallPurchaseSuccess")
    static let paywallPurchaseFailure = Notification.Name("ai.appdna.paywallPurchaseFailure")
}

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

    /// Present a paywall by placement — selects best match using audience rules.
    /// Falls back to first paywall with matching placement if no audience rules match.
    func presentByPlacement(
        placement: String,
        from viewController: UIViewController,
        context: PaywallContext?,
        delegate: AppDNAPaywallDelegate?
    ) {
        let allPaywalls = remoteConfigManager.getAllPaywalls()
        let userTraits = AppDNA.getUserTraits()

        // Filter by placement, then by audience rules, sort by priority
        let candidates = allPaywalls.values
            .filter { $0.placement == placement }
            .sorted {
                let p0 = ($0.audience_rules?.value as? [String: Any])?["priority"] as? Int ?? 0
                let p1 = ($1.audience_rules?.value as? [String: Any])?["priority"] as? Int ?? 0
                return p0 > p1
            }

        // Find first that matches audience rules
        let match = candidates.first { pw in
            guard pw.audience_rules != nil else { return true } // No rules = matches all
            return AudienceRuleEvaluator.evaluate(rules: pw.audience_rules, traits: userTraits)
        }

        guard let config = match else {
            Log.warning("No paywall found for placement: \(placement)")
            return
        }

        present(id: config.id ?? "", from: viewController, context: context, delegate: delegate)
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
            onPlanSelected: { [weak self] plan, metadata in
                self?.handlePurchase(paywallId: id, plan: plan, config: config, metadata: metadata, delegate: delegate, viewController: viewController)
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
            },
            onPromoCodeSubmit: delegate == nil ? nil : { code, completion in
                delegate?.onPromoCodeSubmit(paywallId: id, code: code, completion: completion)
            }
        )

        let hostingController = UIHostingController(rootView: paywallView)
        hostingController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        viewController.present(hostingController, animated: true) {
            delegate?.onPaywallPresented(paywallId: id)
        }
    }

    // MARK: - Purchase flow

    private func handlePurchase(paywallId: String, plan: PaywallPlan, config: PaywallConfig, metadata: [String: Any] = [:], delegate: AppDNAPaywallDelegate?, viewController: UIViewController) {
        guard let bridge = billingBridge else {
            Log.error("No billing bridge configured")
            return
        }

        delegate?.onPaywallPurchaseStarted(paywallId: paywallId, productId: plan.productId ?? "")
        // AC-038: Include toggle states and promo code in purchase event
        var purchaseProps: [String: Any] = [
            "paywall_id": paywallId,
            "product_id": plan.productId,
        ]
        for (key, value) in metadata {
            purchaseProps[key] = value
        }
        eventTracker.track(event: "purchase_started", properties: purchaseProps)

        Task {
            do {
                let result = try await bridge.purchase(productId: plan.productId ?? "")
                eventTracker.track(event: "purchase_completed", properties: [
                    "paywall_id": paywallId,
                    "product_id": result.productId,
                    "price": result.price,
                    "currency": result.currency,
                    "provider": result.provider,
                ])
                DispatchQueue.main.async { [weak self] in
                    delegate?.onPaywallPurchaseCompleted(
                        paywallId: paywallId,
                        productId: result.productId,
                        transaction: TransactionInfo(
                            transactionId: result.transactionId,
                            productId: result.productId,
                            purchaseDate: Date()
                        )
                    )
                    // Post-purchase success action
                    self?.handlePostPurchaseSuccess(
                        config: config.post_purchase?.on_success,
                        paywallId: paywallId,
                        delegate: delegate,
                        viewController: viewController
                    )
                }
            } catch {
                eventTracker.track(event: "purchase_failed", properties: [
                    "paywall_id": paywallId,
                    "product_id": plan.productId,
                    "error": error.localizedDescription,
                ])
                DispatchQueue.main.async { [weak self] in
                    delegate?.onPaywallPurchaseFailed(
                        paywallId: paywallId,
                        error: error
                    )
                    // Post-purchase failure action
                    self?.handlePostPurchaseFailure(
                        config: config.post_purchase?.on_failure,
                        paywallId: paywallId,
                        viewController: viewController
                    )
                }
            }
        }
    }

    // MARK: - Post-purchase actions

    private func handlePostPurchaseSuccess(config: PostPurchaseSuccessConfig?, paywallId: String, delegate: AppDNAPaywallDelegate?, viewController: UIViewController) {
        guard let config = config else { return } // No config = legacy behavior (delegate-only)
        let delay = Double(config.delay_ms ?? 2000) / 1000.0

        switch config.action {
        case "dismiss":
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                viewController.dismiss(animated: true)
            }

        case "show_message":
            // Show success overlay via notification (PaywallRenderer listens)
            NotificationCenter.default.post(name: .paywallPurchaseSuccess, object: nil, userInfo: [
                "message": config.message ?? "Welcome to Premium!",
                "confetti": config.confetti ?? false,
                "lottie_url": config.lottie_url ?? "",
                "delay_ms": config.delay_ms ?? 2000,
            ])
            // Auto-dismiss after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                viewController.dismiss(animated: true) {
                    delegate?.onPaywallDismissed(paywallId: paywallId)
                }
            }

        case "deep_link":
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                viewController.dismiss(animated: true) {
                    delegate?.onPaywallDismissed(paywallId: paywallId)
                    if let url = config.deep_link_url {
                        delegate?.onPostPurchaseDeepLink(paywallId: paywallId, url: url)
                    }
                }
            }

        case "next_step":
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                viewController.dismiss(animated: true) {
                    delegate?.onPaywallDismissed(paywallId: paywallId)
                    delegate?.onPostPurchaseNextStep(paywallId: paywallId)
                }
            }

        default:
            break
        }
    }

    private func handlePostPurchaseFailure(config: PostPurchaseFailureConfig?, paywallId: String, viewController: UIViewController) {
        guard let config = config else { return }

        switch config.action {
        case "dismiss":
            viewController.dismiss(animated: true)

        case "show_error", "retry":
            // Show error inline via notification (PaywallRenderer listens)
            NotificationCenter.default.post(name: .paywallPurchaseFailure, object: nil, userInfo: [
                "message": config.message ?? "Payment failed. Please try again.",
                "retry_text": config.retry_text ?? "Try Again",
                "allow_dismiss": config.allow_dismiss ?? true,
                "action": config.action,
            ])

        default:
            break
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
