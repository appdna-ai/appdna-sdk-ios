import Foundation

/// All possible actions that a section can dispatch through its context.
public enum SectionAction {
    case next
    case back
    case dismiss
    case navigate(screenId: String)
    case openURL(url: String)
    case openWebview(url: String)
    case openAppSettings
    case share(text: String)
    case deepLink(url: String)
    case showPaywall(id: String?)
    case showSurvey(id: String?)
    case showScreen(id: String)
    case submitForm(data: [String: Any])
    case track(event: String, properties: [String: Any]?)
    case haptic(type: String)
    case custom(type: String, value: String?)
}
