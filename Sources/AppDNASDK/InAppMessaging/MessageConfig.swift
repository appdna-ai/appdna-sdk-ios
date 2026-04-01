import Foundation

// MARK: - Firestore schema types for in-app messages

/// Root config from Firestore `/config/messages`.
struct MessageRoot: Codable {
    let version: Int?
    let messages: [String: MessageConfig]?
}

/// A single in-app message definition.
public struct MessageConfig: Codable {
    public let name: String?
    public let message_type: MessageType?
    public let content: MessageContent?
    public let trigger_rules: TriggerRules?
    public let priority: Int?
    public let start_date: String?
    public let end_date: String?
}

public enum MessageType: String, Codable {
    case banner
    case modal
    case fullscreen
    case tooltip
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = MessageType(rawValue: rawValue) ?? .unknown
    }
}

/// Message display content.
public struct MessageContent: Codable {
    public let title: String?
    public let body: String?
    public let image_url: String?
    public let cta_text: String?
    public let cta_action: CTAAction?
    public let dismiss_text: String?
    public let background_color: String?
    public let banner_position: BannerPosition?
    public let auto_dismiss_seconds: Int?
    // SPEC-084: Styling fields
    public let text_color: String?
    public let button_color: String?
    public let button_text_color: String?
    public let button_corner_radius: Int?
    public let corner_radius: Int?
    public let secondary_cta_text: String?
    // SPEC-085: Rich media fields
    public let lottie_url: String?
    public let rive_url: String?
    public let rive_state_machine: String?
    public let video_url: String?
    public let video_thumbnail_url: String?
    public let cta_icon: IconReference?
    public let secondary_cta_icon: IconReference?
    public let haptic: HapticConfig?
    public let particle_effect: ParticleEffect?
    public let blur_backdrop: BlurConfig?
}

public struct CTAAction: Codable {
    public let type: CTAActionType?
    public let url: String?

    public enum CTAActionType: String, Codable {
        case dismiss
        case deep_link
        case open_url
        case unknown

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = CTAActionType(rawValue: rawValue) ?? .unknown
        }
    }
}

public enum BannerPosition: String, Codable {
    case top
    case bottom

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = BannerPosition(rawValue: rawValue) ?? .bottom
    }
}

/// Rules that determine when a message triggers.
public struct TriggerRules: Codable {
    public let event: String?
    public let conditions: [TriggerCondition]?
    public let frequency: MessageFrequency?
    public let max_displays: Int?
    public let delay_seconds: Int?
}

public enum MessageFrequency: String, Codable {
    case once
    case once_per_session
    case every_time
    case max_times

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = MessageFrequency(rawValue: rawValue) ?? .once
    }
}

/// A condition that must be met for a message to trigger.
public struct TriggerCondition: Codable {
    public let field: String?
    public let `operator`: ConditionOperator?
    public let value: AnyCodable?

    public enum ConditionOperator: String, Codable {
        case eq
        case gte
        case lte
        case gt
        case lt
        case contains

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = ConditionOperator(rawValue: rawValue) ?? .eq
        }
    }
}
