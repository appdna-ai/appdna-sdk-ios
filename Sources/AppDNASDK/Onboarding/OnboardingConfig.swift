import Foundation

// MARK: - Firestore schema types for onboarding flows

/// Root onboarding config from Firestore `/config/onboarding`.
struct OnboardingFlowRoot: Codable {
    let flows: [String: OnboardingFlowConfig]?
    let active_flow_id: String?
}

/// A single onboarding flow definition.
public struct OnboardingFlowConfig: Codable {
    public let id: String
    public let name: String?
    public let version: Int?
    private let _steps: [OnboardingStep]?
    private let _settings: OnboardingSettings?
    public let status: String?
    public let graph_layout: AnyCodable?
    /// Lightweight extract of SDK-relevant graph nodes (paywall_trigger, login, end).
    /// Keyed by node ID for O(1) lookup. Preferred over graph_layout for SDK use.
    public let graph_nodes: AnyCodable?
    public let audience_rules: AnyCodable?

    /// Non-optional steps for renderer compatibility
    public var steps: [OnboardingStep] { _steps ?? [] }
    /// Non-optional settings for renderer compatibility
    public var settings: OnboardingSettings { _settings ?? OnboardingSettings() }

    enum CodingKeys: String, CodingKey {
        case id, name, version, _steps = "steps", _settings = "settings"
        case status, graph_layout, graph_nodes, audience_rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version)
        self._steps = try c.decodeIfPresent([OnboardingStep].self, forKey: ._steps)
        self._settings = try c.decodeIfPresent(OnboardingSettings.self, forKey: ._settings)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.graph_layout = try c.decodeIfPresent(AnyCodable.self, forKey: .graph_layout)
        self.graph_nodes = try c.decodeIfPresent(AnyCodable.self, forKey: .graph_nodes)
        self.audience_rules = try c.decodeIfPresent(AnyCodable.self, forKey: .audience_rules)
    }

    /// Convenience memberwise init for tests and manual construction.
    public init(id: String = "", name: String? = nil, version: Int? = nil, steps: [OnboardingStep] = [], settings: OnboardingSettings = OnboardingSettings()) {
        self.id = id
        self.name = name
        self.version = version
        self._steps = steps
        self._settings = settings
        self.status = nil
        self.graph_layout = nil
        self.graph_nodes = nil
        self.audience_rules = nil
    }
}

/// Flow-level settings.
public struct BackButtonStyle: Codable {
    public let icon_size: CGFloat?
    public let icon_color: String?
    public let position: String?  // "left" | "right"
}

public struct OnboardingSettings: Codable {
    public let show_progress: Bool
    public let allow_back: Bool
    public let skip_to_step: String?
    public let progress_style: String?  // "dots" | "segmented_bar" | "continuous_bar" | "fraction" | "none"
    public let progress_color: String?
    public let progress_track_color: String?
    public let back_button_style: BackButtonStyle?
    public let dismiss_allowed: Bool?
    /// Global horizontal content padding in points. Default 24.
    public let content_padding: CGFloat?
    /// Global vertical spacing between content blocks in points. Default 12.
    public let block_spacing: CGFloat?

    public init(show_progress: Bool = true, allow_back: Bool = true, skip_to_step: String? = nil,
                progress_style: String? = nil, progress_color: String? = nil, progress_track_color: String? = nil,
                back_button_style: BackButtonStyle? = nil, dismiss_allowed: Bool? = nil,
                content_padding: CGFloat? = nil, block_spacing: CGFloat? = nil) {
        self.show_progress = show_progress
        self.allow_back = allow_back
        self.skip_to_step = skip_to_step
        self.progress_style = progress_style
        self.progress_color = progress_color
        self.progress_track_color = progress_track_color
        self.back_button_style = back_button_style
        self.dismiss_allowed = dismiss_allowed
        self.content_padding = content_padding
        self.block_spacing = block_spacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.show_progress = try c.decodeIfPresent(Bool.self, forKey: .show_progress) ?? true
        self.allow_back = try c.decodeIfPresent(Bool.self, forKey: .allow_back) ?? true
        self.skip_to_step = try c.decodeIfPresent(String.self, forKey: .skip_to_step)
        self.progress_style = try c.decodeIfPresent(String.self, forKey: .progress_style)
        self.progress_color = try c.decodeIfPresent(String.self, forKey: .progress_color)
        self.progress_track_color = try c.decodeIfPresent(String.self, forKey: .progress_track_color)
        self.back_button_style = try c.decodeIfPresent(BackButtonStyle.self, forKey: .back_button_style)
        self.dismiss_allowed = try c.decodeIfPresent(Bool.self, forKey: .dismiss_allowed)
        self.content_padding = try c.decodeIfPresent(CGFloat.self, forKey: .content_padding)
        self.block_spacing = try c.decodeIfPresent(CGFloat.self, forKey: .block_spacing)
    }

    enum CodingKeys: String, CodingKey {
        case show_progress, allow_back, skip_to_step, progress_style
        case progress_color, progress_track_color, back_button_style, dismiss_allowed
        case content_padding, block_spacing
    }
}

/// A single step within a flow.
/// Next step rule for conditional routing.
public struct NextStepRule: Codable {
    public let condition: AnyCodable?  // "always" or {type: "answer_equals", ...} — backward compat
    public let conditions: [AnyCodable]?  // Array of conditions (preferred)
    public let logic: String?  // "and" | "or" — how to combine conditions
    public let target_step_id: String
}

/// A single step within a flow.
public struct OnboardingStep: Codable, Identifiable {
    public let id: String
    public let type: StepType
    public let config: StepConfig
    public let hook: StepHookConfig?
    public let next_step_rules: [NextStepRule]?
    /// When true, the progress indicator is hidden on this step but the step still counts toward total progress.
    public let hide_progress: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, type, config, layout, hook, hide_progress, content_blocks, next_step_rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try c.decodeIfPresent(StepType.self, forKey: .type) ?? .custom
        self.hook = try c.decodeIfPresent(StepHookConfig.self, forKey: .hook)
        self.hide_progress = try c.decodeIfPresent(Bool.self, forKey: .hide_progress)
        // Read next_step_rules from step level, but also check layout.next_step_rules
        // which may have richer conditions from the Logic panel
        let stepRules = try c.decodeIfPresent([NextStepRule].self, forKey: .next_step_rules)

        // Server writes step content as "layout" or "config" depending on source.
        // Also, content_blocks may be at step level. Try all locations.
        var decoded = try c.decodeIfPresent(StepConfig.self, forKey: .config)
            ?? c.decodeIfPresent(StepConfig.self, forKey: .layout)
            ?? StepConfig()

        // If content_blocks empty in config/layout, check step-level content_blocks
        if (decoded.content_blocks ?? []).isEmpty {
            if let stepBlocks = try c.decodeIfPresent([ContentBlock].self, forKey: .content_blocks), !stepBlocks.isEmpty {
                decoded = StepConfig(
                    title: decoded.title, subtitle: decoded.subtitle, image_url: decoded.image_url,
                    cta_text: decoded.cta_text, skip_enabled: decoded.skip_enabled,
                    options: decoded.options, selection_mode: decoded.selection_mode,
                    items: decoded.items, layout: decoded.layout,
                    fields: decoded.fields, validation_mode: decoded.validation_mode,
                    field_defaults: decoded.field_defaults, chat_config: decoded.chat_config,
                    content_blocks: stepBlocks, layout_variant: decoded.layout_variant,
                    background: decoded.background, text_style: decoded.text_style,
                    element_style: decoded.element_style, animation: decoded.animation,
                    localizations: decoded.localizations, default_locale: decoded.default_locale
                )
            }
        }
        self.config = decoded
        self.next_step_rules = stepRules
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(config, forKey: .config)
        try c.encodeIfPresent(hook, forKey: .hook)
        try c.encodeIfPresent(hide_progress, forKey: .hide_progress)
        try c.encodeIfPresent(next_step_rules, forKey: .next_step_rules)
    }

    public init(id: String = "", type: StepType = .custom, config: StepConfig = StepConfig(), hook: StepHookConfig? = nil, hide_progress: Bool? = nil, next_step_rules: [NextStepRule]? = nil) {
        self.id = id
        self.type = type
        self.config = config
        self.hook = hook
        self.hide_progress = hide_progress
        self.next_step_rules = next_step_rules
    }

    public enum StepType: String, Codable, Equatable {
        case welcome
        case question
        case value_prop
        case custom
        case form
        case interactive_chat

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = StepType(rawValue: rawValue) ?? .custom
        }
    }
}

// MARK: - Step Hook Config (SPEC-083 P1)

/// Server-side webhook configuration for a step.
public struct StepHookConfig: Codable {
    public let enabled: Bool?
    public let webhook_url: String?
    public let timeout_ms: Int?
    public let loading_text: String?
    public let error_text: String?
    public let retry_count: Int?
    public let headers: [String: String]?
}

/// Step configuration — varies by step type.
public struct StepConfig: Codable {
    // welcome
    public let title: String?
    public let subtitle: String?
    public let image_url: String?
    public let cta_text: String?
    public let skip_enabled: Bool?

    // question
    public let options: [QuestionOption]?
    public let selection_mode: SelectionMode?

    // value_prop
    public let items: [ValuePropItem]?

    // custom
    public let layout: [String: AnyCodable]?

    // form (SPEC-082)
    public let fields: [FormField]?
    public let validation_mode: String?  // "on_submit" or "realtime"

    // SPEC-083: Populated by applyOverrides from StepConfigOverride.fieldDefaults
    public let field_defaults: [String: AnyCodable]?

    // SPEC-090: Interactive chat
    public let chat_config: ChatConfig?

    // SPEC-084: Content blocks (block-based step rendering)
    public let content_blocks: [ContentBlock]?
    public let layout_variant: String?   // image_top, image_bottom, image_fullscreen, image_split, no_image
    public let background: BackgroundStyleConfig?
    public let text_style: TextStyleConfig?
    public let element_style: ElementStyleConfig?
    public let animation: AnimationConfig?
    public let localizations: [String: [String: String]]?
    public let default_locale: String?
    // Navigation rules from layout (may have Logic panel conditions)
    public let next_step_rules: [NextStepRule]?
    // Per-step progress bar color override (overrides flow.settings.progress_color)
    public let progress_color: String?

    private enum CodingKeys: String, CodingKey {
        case title, subtitle, image_url, cta_text, skip_enabled
        case options, selection_mode, items, layout, next_step_rules
        case fields, validation_mode, field_defaults
        case chat_config
        case content_blocks, layout_variant, background
        case text_style, element_style, animation
        case localizations, default_locale
        case progress_color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        image_url = try c.decodeIfPresent(String.self, forKey: .image_url)
        cta_text = try c.decodeIfPresent(String.self, forKey: .cta_text)
        skip_enabled = try c.decodeIfPresent(Bool.self, forKey: .skip_enabled)
        options = try c.decodeIfPresent([QuestionOption].self, forKey: .options)
        selection_mode = try c.decodeIfPresent(SelectionMode.self, forKey: .selection_mode)
        items = try c.decodeIfPresent([ValuePropItem].self, forKey: .items)
        layout = try c.decodeIfPresent([String: AnyCodable].self, forKey: .layout)
        fields = try c.decodeIfPresent([FormField].self, forKey: .fields)
        validation_mode = try c.decodeIfPresent(String.self, forKey: .validation_mode)
        field_defaults = nil  // Never from JSON; only set via applyOverrides
        chat_config = try c.decodeIfPresent(ChatConfig.self, forKey: .chat_config)
        content_blocks = try c.decodeIfPresent([ContentBlock].self, forKey: .content_blocks)
        layout_variant = try c.decodeIfPresent(String.self, forKey: .layout_variant)
        background = try c.decodeIfPresent(BackgroundStyleConfig.self, forKey: .background)
        text_style = try c.decodeIfPresent(TextStyleConfig.self, forKey: .text_style)
        element_style = try c.decodeIfPresent(ElementStyleConfig.self, forKey: .element_style)
        animation = try c.decodeIfPresent(AnimationConfig.self, forKey: .animation)
        localizations = try c.decodeIfPresent([String: [String: String]].self, forKey: .localizations)
        default_locale = try c.decodeIfPresent(String.self, forKey: .default_locale)
        next_step_rules = try c.decodeIfPresent([NextStepRule].self, forKey: .next_step_rules)
        progress_color = try c.decodeIfPresent(String.self, forKey: .progress_color)
    }

    // Public memberwise init used by applyOverrides and default construction
    public init(
        title: String? = nil, subtitle: String? = nil, image_url: String? = nil,
        cta_text: String? = nil, skip_enabled: Bool? = nil,
        options: [QuestionOption]? = nil, selection_mode: SelectionMode? = nil,
        items: [ValuePropItem]? = nil, layout: [String: AnyCodable]? = nil,
        fields: [FormField]? = nil, validation_mode: String? = nil,
        field_defaults: [String: AnyCodable]? = nil,
        chat_config: ChatConfig? = nil,
        content_blocks: [ContentBlock]? = nil, layout_variant: String? = nil,
        background: BackgroundStyleConfig? = nil, text_style: TextStyleConfig? = nil,
        element_style: ElementStyleConfig? = nil, animation: AnimationConfig? = nil,
        localizations: [String: [String: String]]? = nil, default_locale: String? = nil,
        next_step_rules: [NextStepRule]? = nil,
        progress_color: String? = nil
    ) {
        self.title = title; self.subtitle = subtitle; self.image_url = image_url
        self.cta_text = cta_text; self.skip_enabled = skip_enabled
        self.options = options; self.selection_mode = selection_mode
        self.items = items; self.layout = layout
        self.fields = fields; self.validation_mode = validation_mode
        self.field_defaults = field_defaults; self.chat_config = chat_config
        self.content_blocks = content_blocks; self.layout_variant = layout_variant
        self.background = background; self.text_style = text_style
        self.element_style = element_style; self.animation = animation
        self.localizations = localizations; self.default_locale = default_locale
        self.next_step_rules = next_step_rules
        self.progress_color = progress_color
    }
}

public struct QuestionOption: Codable, Identifiable {
    public let id: String?
    public let label: String?
    public let icon: String?
    public let subtitle: String?
}

public enum SelectionMode: String, Codable {
    case single
    case multi

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = SelectionMode(rawValue: rawValue) ?? .single
    }
}

public struct ValuePropItem: Codable, Identifiable {
    public let icon: String?
    public let title: String?
    public let subtitle: String?

    public var id: String { title ?? UUID().uuidString }
}

// MARK: - Form Field Types (SPEC-082)

public enum FormFieldType: String, Codable {
    case text, textarea, number, email, phone
    case date, time, datetime
    case select, slider, toggle, stepper, segmented
    case location

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FormFieldType(rawValue: rawValue) ?? .text
    }
}

public struct FormFieldOption: Codable, Identifiable {
    public let id: String?
    public let label: String?
    public let icon: String?
    public let value: AnyCodable?
}

public struct FormFieldValidation: Codable {
    public let pattern: String?
    public let pattern_message: String?
}

public struct FormFieldDependency: Codable {
    public let field_id: String?
    public let operator_type: String?  // equals, not_equals, contains, not_empty, empty, gt, lt, is_set
    public let value: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case field_id
        case operator_type = "operator"
        case value
    }
}

public struct FormFieldConfig: Codable {
    public let max_length: Int?
    public let keyboard_type: String?
    public let autocapitalize: String?
    public let min_value: Double?
    public let max_value: Double?
    public let step: Double?
    public let unit: String?
    public let decimal_places: Int?
    public let min_date: String?
    public let max_date: String?
    public let picker_style: String?
    public let search_enabled: Bool?
    public let multi_select: Bool?
    public let default_value: AnyCodable?
    // Location (SPEC-089)
    public let location_type: String?
    public let location_bias_country: String?
    public let location_language: String?
    public let location_placeholder: String?
    public let location_min_chars: Int?
}

public struct FormField: Codable, Identifiable {
    public let id: String
    public let type: FormFieldType
    public let label: String
    public let placeholder: String?
    public let required: Bool
    public let validation: FormFieldValidation?
    public let options: [FormFieldOption]?
    public let config: FormFieldConfig?
    public let depends_on: FormFieldDependency?

    private enum CodingKeys: String, CodingKey {
        case id, type, label, placeholder, required, validation, options, config, depends_on
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try c.decodeIfPresent(FormFieldType.self, forKey: .type) ?? .text
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        self.required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.validation = try c.decodeIfPresent(FormFieldValidation.self, forKey: .validation)
        self.options = try c.decodeIfPresent([FormFieldOption].self, forKey: .options)
        self.config = try c.decodeIfPresent(FormFieldConfig.self, forKey: .config)
        self.depends_on = try c.decodeIfPresent(FormFieldDependency.self, forKey: .depends_on)
    }
}

// MARK: - Async Step Hook Types (SPEC-083)

/// Result of the async step hook called before advancing.
public enum StepAdvanceResult {
    /// Continue to next step normally.
    case proceed

    /// Continue to next step, merging additional data into responses.
    case proceedWithData([String: Any])

    /// Block advancement. Stay on current step and display error message.
    case block(message: String)

    /// Skip to a specific step by ID (override next_step_rules).
    case skipTo(stepId: String)

    /// Skip to a specific step, merging data.
    case skipToWithData(stepId: String, data: [String: Any])

    /// Stay on the current step without advancing and without showing an error.
    /// Use this when your hook handled the user's action (e.g., sent a password
    /// reset email, displayed a success popup yourself) and you want the user to
    /// remain on the same step.
    ///
    /// - Parameter message: Optional non-error message to display as a success
    ///   toast/banner. Pass `nil` to stay silently — your code handles all UI.
    ///   Pass a non-empty string and the SDK renders it in success styling
    ///   (distinct from `.block`'s error styling).
    case stay(message: String? = nil)
}

/// Optional config override for dynamic step content.
public struct StepConfigOverride {
    /// Override field values (for form steps — pre-fill fields).
    public var fieldDefaults: [String: Any]?

    /// Override title text.
    public var title: String?

    /// Override subtitle text.
    public var subtitle: String?

    /// Override CTA text.
    public var ctaText: String?

    /// Additional layout overrides (merged into step config).
    public var layoutOverrides: [String: Any]?

    public init(
        fieldDefaults: [String: Any]? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        ctaText: String? = nil,
        layoutOverrides: [String: Any]? = nil
    ) {
        self.fieldDefaults = fieldDefaults
        self.title = title
        self.subtitle = subtitle
        self.ctaText = ctaText
        self.layoutOverrides = layoutOverrides
    }
}

// MARK: - Delegate protocol

/// Delegate for receiving onboarding flow lifecycle events.
public protocol AppDNAOnboardingDelegate: AnyObject {
    // Observe-only callbacks (unchanged)
    func onOnboardingStarted(flowId: String)
    func onOnboardingStepChanged(flowId: String, stepId: String, stepIndex: Int, totalSteps: Int)
    func onOnboardingCompleted(flowId: String, responses: [String: Any])
    func onOnboardingDismissed(flowId: String, atStep: Int)

    // SPEC-083: Async hook called BEFORE advancing from a step.
    func onBeforeStepAdvance(
        flowId: String,
        fromStepId: String,
        stepIndex: Int,
        stepType: String,
        responses: [String: Any],
        stepData: [String: Any]?
    ) async -> StepAdvanceResult

    // SPEC-083: Optional hook to modify step config before rendering.
    func onBeforeStepRender(
        flowId: String,
        stepId: String,
        stepIndex: Int,
        stepType: String,
        responses: [String: Any]
    ) async -> StepConfigOverride?
}

/// Default empty implementations so delegates can be partial.
public extension AppDNAOnboardingDelegate {
    func onOnboardingStarted(flowId: String) {}
    func onOnboardingStepChanged(flowId: String, stepId: String, stepIndex: Int, totalSteps: Int) {}
    func onOnboardingCompleted(flowId: String, responses: [String: Any]) {}
    func onOnboardingDismissed(flowId: String, atStep: Int) {}

    func onBeforeStepAdvance(
        flowId: String,
        fromStepId: String,
        stepIndex: Int,
        stepType: String,
        responses: [String: Any],
        stepData: [String: Any]?
    ) async -> StepAdvanceResult {
        return .proceed
    }

    func onBeforeStepRender(
        flowId: String,
        stepId: String,
        stepIndex: Int,
        stepType: String,
        responses: [String: Any]
    ) async -> StepConfigOverride? {
        return nil
    }
}
