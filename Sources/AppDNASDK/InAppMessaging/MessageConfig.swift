import Foundation

// MARK: - Firestore schema types for in-app messages

/// Root config from Firestore `/config/messages`.
struct MessageRoot: Codable {
    let version: Int
    let messages: [String: MessageConfig]
}

/// A single in-app message definition.
public struct MessageConfig: Codable {
    public let name: String
    public let message_type: MessageType
    public let content: MessageContent
    public let trigger_rules: TriggerRules
    public let priority: Int
    public let start_date: String?
    public let end_date: String?
}

public enum MessageType: String, Codable {
    case banner
    case modal
    case fullscreen
    case tooltip
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
}

public struct CTAAction: Codable {
    public let type: CTAActionType
    public let url: String?

    public enum CTAActionType: String, Codable {
        case dismiss
        case deep_link
        case open_url
    }
}

public enum BannerPosition: String, Codable {
    case top
    case bottom
}

/// Rules that determine when a message triggers.
public struct TriggerRules: Codable {
    public let event: String
    public let conditions: [TriggerCondition]?
    public let frequency: MessageFrequency
    public let max_displays: Int?
    public let delay_seconds: Int?
}

public enum MessageFrequency: String, Codable {
    case once
    case once_per_session
    case every_time
    case max_times
}

/// A condition that must be met for a message to trigger.
public struct TriggerCondition: Codable {
    public let field: String
    public let `operator`: ConditionOperator
    public let value: AnyCodable

    public enum ConditionOperator: String, Codable {
        case eq
        case gte
        case lte
        case gt
        case lt
        case contains
    }
}
