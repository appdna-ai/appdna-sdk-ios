import Foundation
import UIKit
import StoreKit

// MARK: - Module Namespaces (v1.0)
// Provides `AppDNA.push.*`, `AppDNA.billing.*`, `AppDNA.onboarding.*`, etc.

extension AppDNA {

    // MARK: - Push Module

    /// Push notification module namespace.
    public final class PushModule: @unchecked Sendable {
        internal weak var manager: PushTokenManager?

        init(manager: PushTokenManager?) {
            self.manager = manager
        }

        /// Request push notification permission and register for remote notifications.
        @discardableResult
        public func requestPermission() async -> Bool {
            return await AppDNA.registerForPush()
        }

        /// Get the current push token string (hex-encoded).
        public var token: String? {
            manager?.currentTokenString
        }

        /// Get the current push token (spec-compliant method form).
        public func getToken() -> String? {
            return manager?.currentTokenString
        }

        /// Set a delegate for push notification events.
        public func setDelegate(_ delegate: AppDNAPushDelegate?) {
            AppDNA.pushDelegate = delegate
        }
    }

    // MARK: - Billing Module

    /// Billing module namespace.
    /// Delegates to the configured `BillingBridgeProtocol` (StoreKit2, RevenueCat, or Adapty).
    public final class BillingModule: @unchecked Sendable {
        internal var bridge: BillingBridgeProtocol?
        private var entitlementChangeHandlers: [([Entitlement]) -> Void] = []

        internal init() {}

        /// Fetch localized product information from the App Store.
        /// Uses StoreKit 2 `Product.products(for:)` directly.
        public func getProducts(_ ids: [String]) async throws -> [ProductInfo] {
            guard bridge != nil else {
                Log.warning("BillingModule: No billing provider configured")
                return []
            }
            let products = try await _fetchStoreKitProducts(ids)
            return products
        }

        /// Initiate a purchase for the given product ID.
        /// Delegates to the configured billing bridge.
        public func purchase(_ productId: String, options: PurchaseOptions? = nil) async throws -> TransactionInfo {
            guard let bridge = bridge else {
                Log.warning("BillingModule: No billing provider configured")
                throw BillingModuleError.noBillingProvider
            }
            let result = try await bridge.purchase(productId: productId)
            return TransactionInfo(
                transactionId: result.transactionId,
                productId: result.productId,
                purchaseDate: Date(),
                environment: "production"
            )
        }

        /// Restore previously purchased products.
        /// Returns an array of restored product IDs.
        public func restorePurchases() async throws -> [String] {
            guard let bridge = bridge else {
                Log.warning("BillingModule: No billing provider configured")
                throw BillingModuleError.noBillingProvider
            }
            return try await bridge.restore()
        }

        /// Get current entitlements as `Entitlement` objects.
        public func getEntitlements() async -> [Entitlement] {
            guard let bridge = bridge else {
                Log.warning("BillingModule: No billing provider configured")
                return []
            }
            let productIds = await bridge.getEntitlements()
            return productIds.map { productId in
                Entitlement(
                    identifier: productId,
                    isActive: true,
                    expiresAt: nil,
                    productId: productId
                )
            }
        }

        /// Check if the user has any active subscription.
        public func hasActiveSubscription() async -> Bool {
            guard let bridge = bridge else { return false }
            let entitlements = await bridge.getEntitlements()
            return !entitlements.isEmpty
        }

        /// Register a callback that fires when entitlements change.
        /// Listens to the internal `entitlementsChanged` notification.
        public func onEntitlementsChanged(_ callback: @escaping ([Entitlement]) -> Void) {
            entitlementChangeHandlers.append(callback)
            NotificationCenter.default.addObserver(
                forName: .entitlementsChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                if let entitlements = notification.userInfo?["entitlements"] as? [ServerEntitlement] {
                    let infos = entitlements.map { e in
                        Entitlement(
                            identifier: e.productId,
                            isActive: e.status == "active" || e.status == "trialing" || e.status == "grace_period",
                            expiresAt: e.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                            productId: e.productId
                        )
                    }
                    callback(infos)
                }
            }
        }

        /// Set a delegate to receive billing lifecycle callbacks.
        public func setDelegate(_ delegate: AppDNABillingDelegate?) {
            AppDNA.billingDelegate = delegate
        }

        /// Internal: Fetch products via StoreKit 2.
        private func _fetchStoreKitProducts(_ ids: [String]) async throws -> [ProductInfo] {
            #if canImport(StoreKit)
            let products = try await StoreKit.Product.products(for: Set(ids))
            var result: [ProductInfo] = []
            for product in products {
                var subInfo: SubscriptionInfo?
                if let sub = product.subscription {
                    let eligible = await sub.isEligibleForIntroOffer
                    subInfo = SubscriptionInfo(
                        period: sub.subscriptionPeriod,
                        introOffer: sub.introductoryOffer,
                        isEligibleForIntroOffer: eligible
                    )
                }
                result.append(ProductInfo(
                    id: product.id,
                    displayName: product.displayName,
                    description: product.description,
                    price: product.price,
                    displayPrice: product.displayPrice,
                    subscription: subInfo
                ))
            }
            return result
            #else
            return []
            #endif
        }
    }

    // MARK: - Onboarding Module

    /// Onboarding module namespace.
    public final class OnboardingModule: @unchecked Sendable {
        internal weak var manager: OnboardingFlowManager?
        internal var delegate: AppDNAOnboardingDelegate?

        init(manager: OnboardingFlowManager?) {
            self.manager = manager
        }

        /// Present an onboarding flow.
        @discardableResult
        public func present(
            flowId: String? = nil,
            from viewController: UIViewController? = nil,
            context: OnboardingContext? = nil
        ) -> Bool {
            return AppDNA.presentOnboarding(flowId: flowId, from: viewController, delegate: delegate)
        }

        /// Set a delegate for onboarding events.
        public func setDelegate(_ delegate: AppDNAOnboardingDelegate?) {
            self.delegate = delegate
        }
    }

    // MARK: - Paywall Module

    /// Paywall module namespace.
    public final class PaywallModule: @unchecked Sendable {
        internal weak var paywallManager: PaywallManager?
        internal var delegate: AppDNAPaywallDelegate?

        init(manager: PaywallManager?) {
            self.paywallManager = manager
        }

        /// Present a paywall.
        public func present(
            _ paywallId: String,
            from viewController: UIViewController? = nil,
            context: PaywallContext? = nil
        ) {
            guard let vc = viewController ?? AppDNA.topViewController() else { return }
            AppDNA.presentPaywall(id: paywallId, from: vc, context: context, delegate: delegate)
        }

        /// Set a delegate for paywall events.
        public func setDelegate(_ delegate: AppDNAPaywallDelegate?) {
            self.delegate = delegate
        }
    }

    // MARK: - Remote Config Module

    /// Remote configuration module namespace.
    public final class RemoteConfigModule: @unchecked Sendable {
        internal weak var manager: RemoteConfigManager?

        init(manager: RemoteConfigManager?) {
            self.manager = manager
        }

        /// Get a remote config value.
        public func get(_ key: String) -> Any? {
            return manager?.getConfig(key: key)
        }

        /// Get all remote config values.
        public func getAll() -> [String: Any] {
            return manager?.getAllConfig() ?? [:]
        }

        /// Force refresh config from server.
        public func refresh() {
            manager?.fetchConfigs()
        }

        /// Listen for config changes.
        public func onChanged(_ handler: @escaping () -> Void) {
            NotificationCenter.default.addObserver(
                forName: AppDNA.configUpdated,
                object: nil,
                queue: .main
            ) { _ in handler() }
        }
    }

    // MARK: - Feature Flags Module

    /// Feature flags module namespace.
    public final class FeaturesModule: @unchecked Sendable {
        internal weak var manager: FeatureFlagManager?

        init(manager: FeatureFlagManager?) {
            self.manager = manager
        }

        /// Check if a feature flag is enabled.
        public func isEnabled(_ flag: String) -> Bool {
            return manager?.isEnabled(flag: flag) ?? false
        }

        /// Get feature flag variant value.
        public func getVariant(_ flag: String) -> Any? {
            return manager?.getValue(flag: flag)
        }

        /// Listen for flag changes.
        public func onChanged(_ handler: @escaping () -> Void) {
            NotificationCenter.default.addObserver(
                forName: AppDNA.configUpdated,
                object: nil,
                queue: .main
            ) { _ in handler() }
        }
    }

    // MARK: - In-App Messages Module

    /// In-app messaging module namespace.
    public final class InAppMessagesModule: @unchecked Sendable {
        internal weak var manager: MessageManager?
        internal var delegate: AppDNAInAppMessageDelegate?

        init(manager: MessageManager?) {
            self.manager = manager
        }

        /// Set a delegate for in-app message events.
        public func setDelegate(_ delegate: AppDNAInAppMessageDelegate?) {
            self.delegate = delegate
        }

        /// Temporarily suppress in-app message display.
        public func suppressDisplay(_ suppress: Bool) {
            manager?.suppressDisplay = suppress
        }
    }

    // MARK: - Surveys Module

    /// Survey module namespace.
    public final class SurveysModule: @unchecked Sendable {
        internal weak var manager: SurveyManager?
        internal var delegate: AppDNASurveyDelegate?

        init(manager: SurveyManager?) {
            self.manager = manager
        }

        /// Present a specific survey.
        public func present(_ surveyId: String) {
            manager?.present(surveyId: surveyId)
        }

        /// Set a delegate for survey events.
        public func setDelegate(_ delegate: AppDNASurveyDelegate?) {
            self.delegate = delegate
        }
    }

    // MARK: - Deep Links Module

    /// Deep links module namespace.
    public final class DeepLinksModule: @unchecked Sendable {
        internal var delegate: AppDNADeepLinkDelegate?

        init() {}

        /// Handle an incoming URL.
        public func handleURL(_ url: URL) {
            delegate?.onDeepLinkReceived(url: url, params: url.queryParameters)
        }

        /// Set a delegate for deep link events.
        public func setDelegate(_ delegate: AppDNADeepLinkDelegate?) {
            self.delegate = delegate
        }
    }

    // MARK: - Experiments Module

    /// Experiments module namespace.
    public final class ExperimentsModule: @unchecked Sendable {
        internal weak var manager: ExperimentManager?

        init(manager: ExperimentManager?) {
            self.manager = manager
        }

        /// Get the assigned variant for an experiment.
        public func getVariant(_ experimentId: String) -> String? {
            return manager?.getVariant(experimentId: experimentId)
        }

        /// Get all active experiment exposures.
        public func getExposures() -> [(experimentId: String, variant: String)] {
            return manager?.getExposures() ?? []
        }
    }
}

// MARK: - Onboarding Context

/// Context passed to onboarding flows for dynamic branching.
public struct OnboardingContext {
    public let source: String?
    public let campaign: String?
    public let referrer: String?
    public let userProperties: [String: Any]?
    public let experimentOverrides: [String: String]?

    public init(
        source: String? = nil,
        campaign: String? = nil,
        referrer: String? = nil,
        userProperties: [String: Any]? = nil,
        experimentOverrides: [String: String]? = nil
    ) {
        self.source = source
        self.campaign = campaign
        self.referrer = referrer
        self.userProperties = userProperties
        self.experimentOverrides = experimentOverrides
    }
}

// MARK: - Purchase Options

/// Options for a billing purchase operation.
public struct PurchaseOptions {
    /// Promotional offer payload, if applicable.
    public let promotionalOffer: PromotionalOfferPayload?
    /// Application-specific account token for fraud detection.
    public let appAccountToken: UUID?

    public init(
        promotionalOffer: PromotionalOfferPayload? = nil,
        appAccountToken: UUID? = nil
    ) {
        self.promotionalOffer = promotionalOffer
        self.appAccountToken = appAccountToken
    }
}

// MARK: - Billing Module Errors

/// Errors specific to the BillingModule namespace.
public enum BillingModuleError: LocalizedError {
    case noBillingProvider

    public var errorDescription: String? {
        switch self {
        case .noBillingProvider:
            return "No billing provider configured. Set billingProvider in AppDNAOptions."
        }
    }
}

// MARK: - URL Query Parameters Helper

private extension URL {
    var queryParameters: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var params: [String: String] = [:]
        for item in items {
            params[item.name] = item.value ?? ""
        }
        return params
    }
}
