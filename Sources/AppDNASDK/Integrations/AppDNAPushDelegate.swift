import Foundation

/// Payload for a push notification delivered to the app.
public struct PushPayload {
    public let pushId: String
    public let title: String
    public let body: String
    public let imageUrl: String?
    public let data: [String: Any]?
    public let action: PushAction?
}

/// Push action from notification tap (deep link, URL, or screen).
public struct PushAction {
    public let type: String
    public let value: String
}

/// Delegate protocol for push notification events.
public protocol AppDNAPushDelegate: AnyObject {
    func onPushTokenRegistered(token: String)
    func onPushReceived(notification: PushPayload, inForeground: Bool)
    func onPushTapped(notification: PushPayload, actionId: String?)
}

/// Default empty implementations so delegates can opt into specific callbacks.
public extension AppDNAPushDelegate {
    func onPushTokenRegistered(token: String) {}
    func onPushReceived(notification: PushPayload, inForeground: Bool) {}
    func onPushTapped(notification: PushPayload, actionId: String?) {}
}
