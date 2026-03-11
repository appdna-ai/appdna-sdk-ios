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
    public let operator_type: String  // equals, not_equals, contains, not_empty, empty, gt, lt
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

// MARK: - Delegate protocol

/// Delegate for receiving onboarding flow lifecycle events.
public protocol AppDNAOnboardingDelegate: AnyObject {
    func onOnboardingStarted(flowId: String)
    func onOnboardingStepChanged(flowId: String, stepId: String, stepIndex: Int, totalSteps: Int)
    func onOnboardingCompleted(flowId: String, responses: [String: Any])
    func onOnboardingDismissed(flowId: String, atStep: Int)
}

/// Default empty implementations so delegates can be partial.
public extension AppDNAOnboardingDelegate {
    func onOnboardingStarted(flowId: String) {}
    func onOnboardingStepChanged(flowId: String, stepId: String, stepIndex: Int, totalSteps: Int) {}
    func onOnboardingCompleted(flowId: String, responses: [String: Any]) {}
    func onOnboardingDismissed(flowId: String, atStep: Int) {}
}
