import Foundation

// MARK: - Screen Config

public struct ScreenConfig: Codable {
    public let id: String
    public let name: String
    public let version: Int?

    // Presentation
    public let presentation: String  // fullscreen, modal, bottom_sheet, push
    public let transition: String?   // slide_up, slide_left, fade, none

    // Layout
    public let layout: ScreenLayout

    // Sections (ordered)
    public let sections: [ScreenSection]

    // Background
    public let background: BackgroundConfig?

    // Dismiss behavior
    public let dismiss: DismissConfig?

    // Navigation bar
    public let nav_bar: NavBarConfig?

    // Haptic & effects
    public let haptic: HapticConfig?
    public let particle_effect: ParticleEffectConfig?

    // Localization
    public let localizations: [String: [String: String]]?
    public let default_locale: String?

    // Targeting
    public let audience_rules: [[String: AnyCodable]]?
    public let trigger_rules: UnifiedTriggerRules?

    // Slot config
    public let slot_config: SlotConfig?

    // Scheduling
    public let start_date: String?
    public let end_date: String?
    public let min_sdk_version: String?

    // Experiments
    public let experiment_id: String?
    public let variants: [String: ScreenVariantOverride]?

    // Analytics
    public let analytics_name: String?
}

// MARK: - Flow Config

public struct FlowConfig: Codable {
    public let id: String
    public let name: String
    public let version: Int?

    public let screens: [FlowScreenRef]
    public let start_screen_id: String
    public let settings: FlowSettings

    public let audience_rules: [[String: AnyCodable]]?
    public let trigger_rules: UnifiedTriggerRules?
}

public struct FlowScreenRef: Codable {
    public let screen_id: String
    public let navigation_rules: [NavigationRule]
}

public struct NavigationRule: Codable {
    public let condition: String  // always, when_equals, when_not_equals, when_gt, when_lt, when_not_empty
    public let variable: String?
    public let value: AnyCodable?
    public let target: String     // "next", "end", or screen_id
    public let transition: String?
}

public struct FlowSettings: Codable {
    public let show_progress: Bool?
    public let allow_back: Bool?
    public let dismiss_enabled: Bool?
    public let persist_state: Bool?
}

// MARK: - Screen Section

public struct ScreenSection: Codable, Identifiable {
    public let id: String
    public let type: String
    public let data: [String: AnyCodable]
    public let style: SectionStyle?
    public let visibility_condition: VisibilityConditionConfig?
    public let entrance_animation: EntranceAnimationConfig?
    public let a11y: AccessibilityConfig?
}

public struct SectionStyle: Codable {
    public let background_color: String?
    public let background_gradient: GradientConfig?
    public let padding_top: Double?
    public let padding_right: Double?
    public let padding_bottom: Double?
    public let padding_left: Double?
    public let margin_top: Double?
    public let margin_bottom: Double?
    public let border_radius: Double?
    public let border_color: String?
    public let border_width: Double?
    public let shadow: ShadowConfig?
    public let opacity: Double?
}

// MARK: - Layout & Presentation

public struct ScreenLayout: Codable {
    public let type: String  // scroll, fixed, pager
    public let padding: Double?
    public let spacing: Double?
    public let safe_area: Bool?
    public let scroll_indicator: Bool?
}

public struct DismissConfig: Codable {
    public let enabled: Bool
    public let style: String?  // x_button, swipe_down, tap_outside, back_button
    public let position: String?  // top_left, top_right
}

public struct NavBarConfig: Codable {
    public let title: String?
    public let show_back: Bool?
    public let show_close: Bool?
    public let style: [String: AnyCodable]?
    public let background_color: String?
}

public struct SlotConfig: Codable {
    public let presentation: String  // inline, overlay
    public let tap_to_expand: Bool?
    public let max_height: Double?
    public let placeholder: PlaceholderConfig?
}

public struct PlaceholderConfig: Codable {
    public let type: String  // skeleton, shimmer, none
    public let height: Double?
}

// MARK: - Styling Sub-Types

public struct BackgroundConfig: Codable {
    public let type: String?  // solid, gradient, image
    public let color: String?
    public let gradient: GradientConfig?
    public let image_url: String?
    public let opacity: Double?
}

public struct GradientConfig: Codable {
    public let angle: Double?
    public let start: String?
    public let end: String?
}

public struct ShadowConfig: Codable {
    public let x: Double?
    public let y: Double?
    public let blur: Double?
    public let spread: Double?
    public let color: String?
}

public struct HapticConfig: Codable {
    public let type: String?  // light, medium, heavy, success, warning, error, selection
    public let on_present: Bool?
}

public struct ParticleEffectConfig: Codable {
    public let type: String?  // confetti, sparkles, snow, fireworks
    public let duration_ms: Int?
    public let intensity: String?  // low, medium, high
    public let on_present: Bool?
}

public struct VisibilityConditionConfig: Codable {
    public let type: String  // always, when_equals, when_not_equals, when_not_empty, when_empty, when_gt, when_lt
    public let variable: String?
    public let value: AnyCodable?
    public let expression: String?
}

public struct EntranceAnimationConfig: Codable {
    public let type: String  // none, fade_in, slide_up, slide_down, slide_left, slide_right, scale_up, bounce, flip
    public let duration_ms: Int?
    public let delay_ms: Int?
    public let easing: String?  // linear, ease, ease_in, ease_out, ease_in_out, spring
    public let spring_damping: Double?
}

public struct AccessibilityConfig: Codable {
    public let label: String?
    public let hint: String?
    public let role: String?  // button, heading, image, link, none
    public let hidden: Bool?
}

// MARK: - Experiment Variants

public struct ScreenVariantOverride: Codable {
    public let sections: [ScreenSection]?
    public let background: BackgroundConfig?
    public let presentation: String?
    public let trigger_rules: UnifiedTriggerRules?
}

// MARK: - Screen Index

public struct ScreenIndex: Codable {
    public let screens: [ScreenIndexEntry]?
    public let flows: [ScreenIndexEntry]?
    public let slots: [SlotAssignment]?
    public let interceptions: [NavigationInterceptionConfig]?
    public let updated_at: String?
}

public struct ScreenIndexEntry: Codable {
    public let id: String
    public let name: String
    public let trigger_rules: UnifiedTriggerRules?
    public let audience_rules: AudienceRuleSet?
    public let priority: Int?
    public let start_date: String?
    public let end_date: String?
    public let min_sdk_version: String?
}

public struct SlotAssignment: Codable {
    public let slot_name: String
    public let screen_id: String
    public let audience_rules: AudienceRuleSet?
}

public struct NavigationInterceptionConfig: Codable {
    public let id: String
    public let trigger_screen: String
    public let timing: String  // before, after
    public let screen_id: String
    public let audience_rules: AudienceRuleSet?
    public let user_traits: [TraitCondition]?
    public let frequency: FrequencyConfig?
}

// MARK: - Results

public enum ScreenError: String, Codable {
    case configFetchFailed
    case configFetchTimeout
    case screenNotFound
    case configParseError
    case configInvalid
    case nestingDepthExceeded
}

public struct ScreenResult {
    public let screenId: String
    public let dismissed: Bool
    public let responses: [String: Any]
    public let lastAction: String?
    public let duration_ms: Int
    public let error: ScreenError?

    public init(screenId: String, dismissed: Bool = false, responses: [String: Any] = [:], lastAction: String? = nil, duration_ms: Int = 0, error: ScreenError? = nil) {
        self.screenId = screenId
        self.dismissed = dismissed
        self.responses = responses
        self.lastAction = lastAction
        self.duration_ms = duration_ms
        self.error = error
    }
}

public struct FlowResult {
    public let flowId: String
    public let completed: Bool
    public let lastScreenId: String
    public let responses: [String: Any]
    public let screensViewed: [String]
    public let duration_ms: Int
    public let error: ScreenError?

    public init(flowId: String, completed: Bool = false, lastScreenId: String = "", responses: [String: Any] = [:], screensViewed: [String] = [], duration_ms: Int = 0, error: ScreenError? = nil) {
        self.flowId = flowId
        self.completed = completed
        self.lastScreenId = lastScreenId
        self.responses = responses
        self.screensViewed = screensViewed
        self.duration_ms = duration_ms
        self.error = error
    }
}
