import Foundation

// MARK: - v1.0 Delegate Protocols
//
// NOTE (SPEC-041): The following delegate protocols are defined in their respective module files
// and are NOT duplicated here to avoid compilation conflicts:
//
//   - AppDNAOnboardingDelegate → Sources/AppDNASDK/Onboarding/OnboardingConfig.swift
//     Methods: onOnboardingStarted, onOnboardingStepChanged, onOnboardingCompleted, onOnboardingDismissed
//
//   - AppDNAPaywallDelegate → Sources/AppDNASDK/Paywalls/PaywallConfig.swift
//     Methods: onPaywallPresented, onPaywallAction, onPaywallPurchaseStarted,
//              onPaywallPurchaseCompleted, onPaywallPurchaseFailed, onPaywallDismissed
//
//   - AppDNAPushDelegate → Sources/AppDNASDK/Integrations/AppDNAPushDelegate.swift
//     Methods: onPushTokenRegistered, onPushReceived, onPushTapped
//

/// Delegate for billing/purchase events.
public protocol AppDNABillingDelegate: AnyObject {
    func onPurchaseCompleted(productId: String, transaction: TransactionInfo)
    func onPurchaseFailed(productId: String, error: Error)
    func onEntitlementsChanged(entitlements: [Entitlement])
    func onRestoreCompleted(restoredProducts: [String])
}

/// Default implementations — all methods optional.
public extension AppDNABillingDelegate {
    func onPurchaseCompleted(productId: String, transaction: TransactionInfo) {}
    func onPurchaseFailed(productId: String, error: Error) {}
    func onEntitlementsChanged(entitlements: [Entitlement]) {}
    func onRestoreCompleted(restoredProducts: [String]) {}
}

/// Delegate for in-app message events.
public protocol AppDNAInAppMessageDelegate: AnyObject {
    func onMessageShown(messageId: String, trigger: String)
    func onMessageAction(messageId: String, action: String, data: [String: Any]?)
    func onMessageDismissed(messageId: String)
    func shouldShowMessage(messageId: String) -> Bool
}

/// Default implementations — all methods optional.
public extension AppDNAInAppMessageDelegate {
    func onMessageShown(messageId: String, trigger: String) {}
    func onMessageAction(messageId: String, action: String, data: [String: Any]?) {}
    func onMessageDismissed(messageId: String) {}
    func shouldShowMessage(messageId: String) -> Bool { true }
}

/// Delegate for survey events.
public protocol AppDNASurveyDelegate: AnyObject {
    func onSurveyPresented(surveyId: String)
    func onSurveyCompleted(surveyId: String, responses: [SurveyResponse])
    func onSurveyDismissed(surveyId: String)
}

/// Default implementations — all methods optional.
public extension AppDNASurveyDelegate {
    func onSurveyPresented(surveyId: String) {}
    func onSurveyCompleted(surveyId: String, responses: [SurveyResponse]) {}
    func onSurveyDismissed(surveyId: String) {}
}

/// Delegate for deep link events.
public protocol AppDNADeepLinkDelegate: AnyObject {
    func onDeepLinkReceived(url: URL, params: [String: String])
}

/// Default implementations — all methods optional.
public extension AppDNADeepLinkDelegate {
    func onDeepLinkReceived(url: URL, params: [String: String]) {}
}

// MARK: - Support Types

/// Transaction info from a completed purchase.
public struct TransactionInfo {
    public let transactionId: String
    public let productId: String
    public let purchaseDate: Date
    public let environment: String

    public init(transactionId: String, productId: String, purchaseDate: Date, environment: String = "production") {
        self.transactionId = transactionId
        self.productId = productId
        self.purchaseDate = purchaseDate
        self.environment = environment
    }
}

/// Entitlement info.
public struct Entitlement {
    public let identifier: String
    public let isActive: Bool
    public let expiresAt: Date?
    public let productId: String

    public init(identifier: String, isActive: Bool, expiresAt: Date? = nil, productId: String) {
        self.identifier = identifier
        self.isActive = isActive
        self.expiresAt = expiresAt
        self.productId = productId
    }
}

/// Survey response.
public struct SurveyResponse {
    public let questionId: String
    public let answer: Any

    public init(questionId: String, answer: Any) {
        self.questionId = questionId
        self.answer = answer
    }
}
