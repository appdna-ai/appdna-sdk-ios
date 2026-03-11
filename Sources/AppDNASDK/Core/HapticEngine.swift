import UIKit

public enum HapticType: String, Codable {
    case light, medium, heavy, selection, success, warning, error
}

public struct HapticConfig: Codable {
    public let enabled: Bool
    public let triggers: HapticTriggers
}

public struct HapticTriggers: Codable {
    public let on_step_advance: HapticType?
    public let on_button_tap: HapticType?
    public let on_plan_select: HapticType?
    public let on_option_select: HapticType?
    public let on_toggle: HapticType?
    public let on_form_submit: HapticType?
    public let on_error: HapticType?
    public let on_success: HapticType?
}

public enum HapticEngine {
    public static func trigger(_ type: HapticType) {
        switch type {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    public static func triggerIfEnabled(_ type: HapticType?, config: HapticConfig?) {
        guard let config = config, config.enabled, let type = type else { return }
        trigger(type)
    }
}
