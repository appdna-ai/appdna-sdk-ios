import Foundation

// MARK: - Firestore schema types for onboarding flows

/// Root onboarding config from Firestore `/config/onboarding`.
struct OnboardingFlowRoot: Codable {
    let flows: [String: OnboardingFlowConfig]
    let active_flow_id: String?
}

/// A single onboarding flow definition.
public struct OnboardingFlowConfig: Codable {
    public let id: String
    public let name: String
    public let version: Int
    public let steps: [OnboardingStep]
    public let settings: OnboardingSettings
}

/// Flow-level settings.
public struct OnboardingSettings: Codable {
    public let show_progress: Bool
    public let allow_back: Bool
    public let skip_to_step: String?

    public init(show_progress: Bool = true, allow_back: Bool = true, skip_to_step: String? = nil) {
        self.show_progress = show_progress
        self.allow_back = allow_back
        self.skip_to_step = skip_to_step
    }
}

/// A single step within a flow.
public struct OnboardingStep: Codable, Identifiable {
    public let id: String
    public let type: StepType
    public let config: StepConfig

    public enum StepType: String, Codable {
        case welcome
        case question
        case value_prop
        case custom
        case form

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = StepType(rawValue: rawValue) ?? .custom
        }
    }
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

    private enum CodingKeys: String, CodingKey {
        case title, subtitle, image_url, cta_text, skip_enabled
        case options, selection_mode, items, layout
        case fields, validation_mode, field_defaults
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
    }

    // Internal memberwise init used by applyOverrides
    init(
        title: String? = nil, subtitle: String? = nil, image_url: String? = nil,
        cta_text: String? = nil, skip_enabled: Bool? = nil,
        options: [QuestionOption]? = nil, selection_mode: SelectionMode? = nil,
        items: [ValuePropItem]? = nil, layout: [String: AnyCodable]? = nil,
        fields: [FormField]? = nil, validation_mode: String? = nil,
        field_defaults: [String: AnyCodable]? = nil
    ) {
        self.title = title; self.subtitle = subtitle; self.image_url = image_url
        self.cta_text = cta_text; self.skip_enabled = skip_enabled
        self.options = options; self.selection_mode = selection_mode
        self.items = items; self.layout = layout
        self.fields = fields; self.validation_mode = validation_mode
        self.field_defaults = field_defaults
    }
}

public struct QuestionOption: Codable, Identifiable {
    public let id: String
    public let label: String
    public let icon: String?
}

public enum SelectionMode: String, Codable {
    case single
    case multi
}

public struct ValuePropItem: Codable, Identifiable {
    public let icon: String
    public let title: String
    public let subtitle: String

    public var id: String { title }
}

// MARK: - Form Field Types (SPEC-082)

public enum FormFieldType: String, Codable {
    case text, textarea, number, email, phone
    case date, time, datetime
    case select, slider, toggle, stepper, segmented

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FormFieldType(rawValue: rawValue) ?? .text
    }
}

public struct FormFieldOption: Codable, Identifiable {
    public let id: String
    public let label: String
    public let icon: String?
    public let value: AnyCodable?
}

public struct FormFieldValidation: Codable {
    public let pattern: String?
    public let pattern_message: String?
}

public struct FormFieldDependency: Codable {
    public let field_id: String
    public let operator_type: String  // equals, not_equals, contains, not_empty, empty, gt, lt, is_set
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
