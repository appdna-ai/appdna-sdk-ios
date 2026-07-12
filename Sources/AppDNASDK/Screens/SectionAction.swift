import Foundation

/// All possible actions that a section can dispatch through its context.
///
/// Mirrors Android `screens/SectionContext.kt` `sealed class SectionAction` case for case: the two
/// platforms must be able to express the SAME action set, or a verb one platform can route is a verb
/// the other silently drops. The nine flow-level verbs below (`restart` … `restore`) were Android-only
/// — `Screens/FlowManager.swift` had no way to even receive them.
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

    // Flow-level verbs — parity with Android `SectionAction` (SectionContext.kt:50-63). Routed by
    // `FlowManager.handleAction`; on the single-screen path they have no meaning and are ignored.
    case restart
    case complete
    case setResponse(key: String, value: Any?)
    case presentPaywall(id: String?)
    case dismissPaywall
    case showMessage(id: String?)
    case setUserProperty(key: String, value: Any?)
    case purchase(productId: String)
    case restore
}
