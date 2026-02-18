import Foundation

// MARK: - Firestore schema types for surveys (SPEC-023)

/// Root config from Firestore `/config/surveys`.
struct SurveyRoot: Codable {
    let version: Int
    let surveys: [String: SurveyConfig]
}

/// A single survey definition.
public struct SurveyConfig: Codable {
    public let name: String
    public let survey_type: String // "nps", "csat", "custom"
    public let questions: [SurveyQuestion]
    public let trigger_rules: SurveyTriggerRules
    public let appearance: SurveyAppearance
    public let follow_up_actions: SurveyFollowUpActions?
}

/// A single survey question.
public struct SurveyQuestion: Codable {
    public let id: String
    public let type: String // "nps", "csat", "rating", "single_choice", "multi_choice", "free_text", "yes_no", "emoji_scale"
    public let text: String
    public let required: Bool
    public let show_if: ShowIfCondition?

    // Type-specific configs
    public let nps_config: NPSConfig?
    public let csat_config: CSATConfig?
    public let rating_config: RatingConfig?
    public let options: [SurveyQuestionOption]?
    public let emoji_config: EmojiConfig?
    public let free_text_config: FreeTextConfig?
}

public struct ShowIfCondition: Codable {
    public let question_id: String
    public let answer_in: [AnyCodable]
}

public struct NPSConfig: Codable {
    public let low_label: String?
    public let high_label: String?
}

public struct CSATConfig: Codable {
    public let max_rating: Int?  // default 5
    public let style: String?    // "star", "emoji"
}

public struct RatingConfig: Codable {
    public let max_rating: Int?  // default 5
    public let style: String?    // "star", "heart", "thumb"
}

public struct SurveyQuestionOption: Codable {
    public let id: String
    public let text: String
    public let icon: String?
}

public struct EmojiConfig: Codable {
    public let emojis: [String]? // default: ["😡","😕","😐","😊","😍"]
}

public struct FreeTextConfig: Codable {
    public let placeholder: String?
    public let max_length: Int? // default 500
}

/// Survey trigger rules.
public struct SurveyTriggerRules: Codable {
    public let event: String
    public let conditions: [TriggerCondition]?
    public let love_score_range: ScoreRange?
    public let frequency: MessageFrequency // reuse from in-app messaging
    public let max_displays: Int?
    public let delay_seconds: Int?
    public let min_sessions: Int?
}

public struct ScoreRange: Codable {
    public let min: Int
    public let max: Int
}

/// Survey appearance settings.
public struct SurveyAppearance: Codable {
    public let presentation: String // "bottom_sheet", "modal", "fullscreen"
    public let theme: SurveyTheme?
    public let dismiss_allowed: Bool
    public let show_progress: Bool
}

public struct SurveyTheme: Codable {
    public let background_color: String?
    public let text_color: String?
    public let accent_color: String?
    public let button_color: String?
}

/// Follow-up actions based on survey sentiment.
public struct SurveyFollowUpActions: Codable {
    public let on_positive: FollowUpAction?
    public let on_negative: FollowUpAction?
    public let on_neutral: FollowUpAction?
}

public struct FollowUpAction: Codable {
    public let action: String // "prompt_review", "show_feedback_form", "dismiss"
    public let message: String?
}

/// A single survey answer.
public struct SurveyAnswer {
    public let question_id: String
    public let answer: Any

    var asDictionary: [String: Any] {
        return ["question_id": question_id, "answer": answer]
    }
}

/// Survey completion result.
public enum SurveyResult {
    case completed(answers: [SurveyAnswer])
    case dismissed(answeredCount: Int)
}

/// Sentiment determination.
enum SurveySentiment {
    case positive
    case negative
    case neutral
}
