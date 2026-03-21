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
    let type: String // "header", "features", "plans", "cta", "social_proof", "guarantee", "image", "spacer", "testimonial", "lottie", "video", "rive", "countdown", "legal", "divider", "sticky_footer", "card", "carousel", "timeline", "icon_grid", "comparison_table", "promo_input", "toggle", "reviews_carousel"
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

    // SPEC-089d: Countdown section
    let variant: String?           // digital | circular | flip | bar
    let durationSeconds: Int?
    let targetDatetime: String?
    let showDays: Bool?
    let showHours: Bool?
    let showMinutes: Bool?
    let showSeconds: Bool?
    let labels: [String: String]?
    let onExpireAction: String?    // hide | show_expired_text | auto_advance
    let expiredText: String?
    let accentColor: String?
    let backgroundColor: String?
    let fontSize: CGFloat?
    let alignment: String?

    // SPEC-089d: Legal section
    let color: String?
    let links: [PaywallLink]?

    // SPEC-089d: Divider section
    let thickness: CGFloat?
    let lineStyle: String?         // solid | dashed | dotted
    let marginTop: CGFloat?
    let marginBottom: CGFloat?
    let marginHorizontal: CGFloat?
    let labelText: String?
    let labelColor: String?
    let labelBgColor: String?
    let labelFontSize: CGFloat?

    // SPEC-089d: Sticky footer section
    let ctaText: String?
    let ctaBgColor: String?
    let ctaTextColor: String?
    let ctaCornerRadius: CGFloat?
    let secondaryText: String?
    let secondaryAction: String?   // restore | link
    let secondaryUrl: String?
    let legalText: String?
    let blurBackground: Bool?
    let padding: CGFloat?

    // SPEC-089d: Carousel section
    let pages: [PaywallCarouselPage]?
    let autoScroll: Bool?
    let autoScrollIntervalMs: Int?
    let showIndicators: Bool?
    let indicatorColor: String?
    let indicatorActiveColor: String?

    // SPEC-089d: Timeline / Icon grid items (shared JSON key "items")
    let items: [PaywallGenericItem]?
    let lineColor: String?
    let completedColor: String?
    let currentColor: String?
    let upcomingColor: String?
    let showLine: Bool?
    let compact: Bool?

    // SPEC-089d: Icon grid / comparison table columns (Int for icon_grid, array for comparison)
    let columns: Int?
    let iconSize: CGFloat?
    let iconColor: String?
    let spacing: CGFloat?

    // SPEC-089d: Comparison table section
    let tableColumns: [PaywallTableColumn]?
    let tableRows: [PaywallTableRow]?
    let checkColor: String?
    let crossColor: String?
    let highlightColor: String?
    let borderColor: String?

    // SPEC-089d: Promo input section
    let placeholder: String?
    let buttonText: String?
    let successText: String?
    let errorText: String?

    // SPEC-089d: Toggle section
    let label: String?
    let description: String?
    let defaultValue: Bool?
    let onColor: String?
    let offColor: String?
    let labelColorVal: String?
    let descriptionColor: String?
    let icon: String?
    let affectsPrice: Bool?

    // SPEC-089d: Reviews carousel section
    let reviews: [PaywallReview]?
    let showRatingStars: Bool?
    let starColor: String?

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
        // SPEC-089d: New section fields
        case variant
        case durationSeconds = "duration_seconds"
        case targetDatetime = "target_datetime"
        case showDays = "show_days"
        case showHours = "show_hours"
        case showMinutes = "show_minutes"
        case showSeconds = "show_seconds"
        case labels
        case onExpireAction = "on_expire_action"
        case expiredText = "expired_text"
        case accentColor = "accent_color"
        case backgroundColor = "background_color"
        case fontSize = "font_size"
        case alignment
        case color, links, thickness
        case lineStyle = "style"
        case marginTop = "margin_top"
        case marginBottom = "margin_bottom"
        case marginHorizontal = "margin_horizontal"
        case labelText = "label_text"
        case labelColor = "label_color"
        case labelBgColor = "label_bg_color"
        case labelFontSize = "label_font_size"
        case ctaText = "cta_text"
        case ctaBgColor = "cta_bg_color"
        case ctaTextColor = "cta_text_color"
        case ctaCornerRadius = "cta_corner_radius"
        case secondaryText = "secondary_text"
        case secondaryAction = "secondary_action"
        case secondaryUrl = "secondary_url"
        case legalText = "legal_text"
        case blurBackground = "blur_background"
        case padding, pages
        case autoScroll = "auto_scroll"
        case autoScrollIntervalMs = "auto_scroll_interval_ms"
        case showIndicators = "show_indicators"
        case indicatorColor = "indicator_color"
        case indicatorActiveColor = "indicator_active_color"
        case items
        case lineColor = "line_color"
        case completedColor = "completed_color"
        case currentColor = "current_color"
        case upcomingColor = "upcoming_color"
        case showLine = "show_line"
        case compact
        case columns
        case iconSize = "icon_size"
        case iconColor = "icon_color"
        case spacing
        case tableColumns = "table_columns"
        case tableRows = "rows"
        case checkColor = "check_color"
        case crossColor = "cross_color"
        case highlightColor = "highlight_color"
        case borderColor = "border_color"
        case placeholder
        case buttonText = "button_text"
        case successText = "success_text"
        case errorText = "error_text"
        case label, description
        case defaultValue = "default_value"
        case onColor = "on_color"
        case offColor = "off_color"
        case labelColorVal = "toggle_label_color"
        case descriptionColor = "description_color"
        case icon
        case affectsPrice = "affects_price"
        case reviews
        case showRatingStars = "show_rating_stars"
        case starColor = "star_color"
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

// MARK: - SPEC-089d: Codable sub-types for new paywall sections

struct PaywallLink: Codable {
    let label: String
    let url: String
}

struct PaywallCarouselPage: Codable, Identifiable {
    let id: String
    let children: [PaywallSection]?

    enum CodingKeys: String, CodingKey {
        case id, children
    }
}

/// Generic item used by timeline and icon_grid sections.
/// Timeline uses: id, title, subtitle, icon, status
/// Icon grid uses: icon, label, description
struct PaywallGenericItem: Codable {
    let id: String?
    let title: String?
    let subtitle: String?
    let icon: String?
    let status: String?       // completed | current | upcoming (timeline)
    let label: String?         // icon_grid
    let description: String?   // icon_grid
}

struct PaywallTableColumn: Codable {
    let label: String
    let highlighted: Bool?
}

struct PaywallTableRow: Codable {
    let feature: String
    let values: [String]
}

struct PaywallReview: Codable, Identifiable {
    let text: String
    let author: String
    let rating: Double?
    let avatarUrl: String?
    let date: String?

    var id: String { author + (text.prefix(20).description) }

    enum CodingKeys: String, CodingKey {
        case text, author, rating, date
        case avatarUrl = "avatar_url"
    }
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
