import Foundation

/// Codable structs matching SPEC-002 Firestore PaywallConfig schema.
struct PaywallConfig: Codable {
    let id: String
    let name: String
    let layout: PaywallLayout
    let sections: [PaywallSection]
    let dismiss: PaywallDismiss?
    let background: PaywallBackground?
}

struct PaywallLayout: Codable {
    let type: String // "stack" or "grid"
    let spacing: CGFloat?
    let padding: CGFloat?
}

struct PaywallSection: Codable {
    let type: String // "header", "features", "plans", "cta", "social_proof", "guarantee"
    let data: PaywallSectionData?
}

struct PaywallSectionData: Codable {
    // Header
    let title: String?
    let subtitle: String?
    let imageUrl: String?

    // Features
    let features: [String]?

    // Plans
    let plans: [PaywallPlan]?

    // CTA
    let cta: PaywallCTA?

    // Social proof
    let rating: Double?
    let reviewCount: Int?
    let testimonial: String?

    // Guarantee
    let guaranteeText: String?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, features, plans, cta, rating, testimonial
        case imageUrl = "image_url"
        case reviewCount = "review_count"
        case guaranteeText = "guarantee_text"
    }
}

struct PaywallPlan: Codable, Identifiable {
    let id: String
    let productId: String
    let name: String
    let price: String
    let period: String?
    let badge: String?
    let trialDuration: String?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, price, period, badge
        case productId = "product_id"
        case trialDuration = "trial_duration"
        case isDefault = "is_default"
    }
}

struct PaywallCTA: Codable {
    let text: String
    let style: String? // "primary", "gradient"
}

struct PaywallDismiss: Codable {
    let type: String // "x_button", "swipe", "text_link"
    let delaySeconds: Int?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type, text
        case delaySeconds = "delay_seconds"
    }
}

struct PaywallBackground: Codable {
    let type: String // "color", "gradient", "image"
    let value: String? // hex color, gradient def, or image URL
    let colors: [String]?
}

// MARK: - Public types

/// Context passed when presenting a paywall.
public struct PaywallContext {
    public let placement: String
    public let experiment: String?
    public let variant: String?

    public init(placement: String, experiment: String? = nil, variant: String? = nil) {
        self.placement = placement
        self.experiment = experiment
        self.variant = variant
    }
}

/// Reason a paywall was dismissed.
public enum DismissReason: String {
    case purchased
    case dismissed
    case tappedOutside
    case programmatic
}

/// Action taken by the user on a paywall.
public enum PaywallAction: String {
    case ctaTapped = "cta_tapped"
    case featureSelected = "feature_selected"
    case planChanged = "plan_changed"
    case linkTapped = "link_tapped"
    case custom = "custom"
}

/// Delegate for paywall lifecycle events.
public protocol AppDNAPaywallDelegate: AnyObject {
    func onPaywallPresented(paywallId: String)
    func onPaywallAction(paywallId: String, action: PaywallAction)
    func onPaywallPurchaseStarted(paywallId: String, productId: String)
    func onPaywallPurchaseCompleted(paywallId: String, productId: String, transaction: TransactionInfo)
    func onPaywallPurchaseFailed(paywallId: String, error: Error)
    func onPaywallDismissed(paywallId: String)
}

/// Default empty implementations so delegates can opt into specific callbacks.
public extension AppDNAPaywallDelegate {
    func onPaywallPresented(paywallId: String) {}
    func onPaywallAction(paywallId: String, action: PaywallAction) {}
    func onPaywallPurchaseStarted(paywallId: String, productId: String) {}
    func onPaywallPurchaseCompleted(paywallId: String, productId: String, transaction: TransactionInfo) {}
    func onPaywallPurchaseFailed(paywallId: String, error: Error) {}
    func onPaywallDismissed(paywallId: String) {}
}
