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
    func onPushReceived(notification: PushPayload)
    func onPushTapped(notification: PushPayload, action: String?)
}
