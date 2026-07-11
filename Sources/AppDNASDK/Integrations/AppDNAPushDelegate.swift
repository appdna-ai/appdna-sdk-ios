import Foundation

/// Payload for a push notification delivered to the app.
public struct PushPayload {
    public let pushId: String
    public let title: String
    public let body: String
    public let imageUrl: String?
    public let data: [String: Any]?
    /// The single `action` object — the tap-through action of the notification body itself.
    /// Populated from the first entry of `actions` when the payload only carries buttons.
    public let action: PushAction?
    /// The notification's action BUTTONS. The server has always sent an `actions` array (the SDK
    /// registers them as `UNNotificationAction`s), but the payload handed to the host exposed only a
    /// single `action` — so a host could see WHICH button was tapped (`actionId`) but had no way to
    /// look up what that button was supposed to do.
    public let actions: [PushAction]

    public init(
        pushId: String,
        title: String,
        body: String,
        imageUrl: String? = nil,
        data: [String: Any]? = nil,
        action: PushAction? = nil,
        actions: [PushAction] = []
    ) {
        self.pushId = pushId
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.data = data
        self.action = action
        self.actions = actions
    }
}

/// Push action from notification tap (deep link, URL, or screen).
public struct PushAction {
    public let type: String
    public let value: String
    /// Button identifier — matches the `actionId` passed to `onPushTapped`. Nil for the
    /// notification-body action, which has no button.
    public let id: String?
    /// Button label as displayed (post template interpolation). Nil for the body action.
    public let label: String?

    public init(type: String, value: String, id: String? = nil, label: String? = nil) {
        self.type = type
        self.value = value
        self.id = id
        self.label = label
    }
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
