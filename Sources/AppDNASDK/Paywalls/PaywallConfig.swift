import Foundation

/// Codable structs matching SPEC-002 Firestore PaywallConfig schema.
struct PaywallConfig: Codable {
    let id: String
    let name: String
    let layout: PaywallLayout
    let sections: [PaywallSection]
    let dismiss: PaywallDismiss?
    let background: PaywallBackground?
    // SPEC-084: Design tokens
    let animation: AnimationConfig?
    let localizations: [String: [String: String]]?
    let default_locale: String?
    // SPEC-085: Rich media
    let haptic: HapticConfig?
    let particle_effect: ParticleEffect?
}

struct PaywallLayout: Codable {
    let type: String // "stack", "grid", "carousel"
    let spacing: CGFloat?
    let padding: CGFloat?
}

struct PaywallSection: Codable {
    let type: String // "header", "features", "plans", "cta", "social_proof", "guarantee", "image", "spacer", "testimonial"
    let data: PaywallSectionData?
    // SPEC-084: Per-section styling
    let style: SectionStyleConfig?
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
    let subType: String?       // "app_rating", "countdown", "trial_badge"
    let countdownSeconds: Int?
    let text: String?

    // Guarantee
    let guaranteeText: String?

    // Image section
    let height: CGFloat?
    let cornerRadius: CGFloat?

    // Spacer section
    let spacerHeight: CGFloat?

    // Testimonial section
    let quote: String?
    let authorName: String?
    let authorRole: String?
    let avatarUrl: String?

    // SPEC-085: Rich media in paywall sections
    let lottieUrl: String?
    let lottieLoop: Bool?
    let lottieSpeed: Double?
    let lottieHeight: CGFloat?
    let videoUrl: String?
    let videoThumbnailUrl: String?
    let videoHeight: CGFloat?
    let riveUrl: String?
    let riveStateMachine: String?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, features, plans, cta, rating, testimonial, text, quote, height
        case imageUrl = "image_url"
        case reviewCount = "review_count"
        case guaranteeText = "guarantee_text"
        case subType = "sub_type"
        case countdownSeconds = "countdown_seconds"
        case cornerRadius = "corner_radius"
        case spacerHeight = "spacer_height"
        case authorName = "author_name"
        case authorRole = "author_role"
        case avatarUrl = "avatar_url"
        case lottieUrl = "lottie_url"
        case lottieLoop = "lottie_loop"
        case lottieSpeed = "lottie_speed"
        case lottieHeight = "lottie_height"
        case videoUrl = "video_url"
        case videoThumbnailUrl = "video_thumbnail_url"
        case videoHeight = "video_height"
        case riveUrl = "rive_url"
        case riveStateMachine = "rive_state_machine"
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
    let type: String // "color", "gradient", "image", "video"
    let value: String? // hex color, gradient def, image URL, or video URL
    let colors: [String]?
    // SPEC-085: Video background
    let video_url: String?
    let video_poster_url: String?
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
