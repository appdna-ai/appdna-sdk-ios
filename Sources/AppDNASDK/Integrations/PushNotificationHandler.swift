import Foundation
import UserNotifications

/// Handles push notification display and tracking.
public class PushNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private weak var eventTracker: EventTracker?
    private weak var pushTokenManager: PushTokenManager?

    init(eventTracker: EventTracker?, pushTokenManager: PushTokenManager?) {
        self.eventTracker = eventTracker
        self.pushTokenManager = pushTokenManager
        super.init()
    }

    /// Called when notification received in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let pushId = userInfo["push_id"] as? String ?? ""
        pushTokenManager?.trackDelivered(pushId: pushId)

        // SPEC-084: Register action categories if present
        registerActionCategories(from: userInfo)

        // Notify delegate
        let payload = buildPayload(from: notification.request.content)
        AppDNA.pushDelegate?.onPushReceived(notification: payload, inForeground: true)

        completionHandler([.banner, .badge, .sound])
    }

    /// Called when user taps notification
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let pushId = userInfo["push_id"] as? String ?? ""
        let actionIdentifier = response.actionIdentifier
        pushTokenManager?.trackTapped(pushId: pushId, action: actionIdentifier)

        // Build payload and notify delegate
        let payload = buildPayload(from: response.notification.request.content)
        let tappedAction = actionIdentifier == UNNotificationDefaultActionIdentifier ? nil : actionIdentifier
        AppDNA.pushDelegate?.onPushTapped(notification: payload, actionId: tappedAction)

        completionHandler()
    }

    // SPEC-084: Register notification categories with action buttons
    func registerActionCategories(from userInfo: [AnyHashable: Any]) {
        guard let actionsData = userInfo["actions"] as? [[String: Any]], !actionsData.isEmpty else { return }
        let categoryId = userInfo["category"] as? String ?? "appdna_default"

        let actions: [UNNotificationAction] = actionsData.compactMap { actionData in
            guard let id = actionData["id"] as? String,
                  let label = actionData["label"] as? String else { return nil }
            let foreground = actionData["foreground"] as? Bool ?? false
            let options: UNNotificationActionOptions = foreground ? [.foreground] : []
            return UNNotificationAction(identifier: id, title: label, options: options)
        }

        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var categories = existing
            categories.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        }
    }

    private func buildPayload(from content: UNNotificationContent) -> PushPayload {
        let userInfo = content.userInfo
        let pushId = userInfo["push_id"] as? String ?? ""
        let imageUrl = userInfo["image_url"] as? String
        let data = userInfo["data"] as? [String: Any]

        var action: PushAction? = nil
        if let actionData = userInfo["action"] as? [String: String],
           let type = actionData["type"], let value = actionData["value"] {
            action = PushAction(type: type, value: value)
        }

        return PushPayload(
            pushId: pushId,
            title: content.title,
            body: content.body,
            imageUrl: imageUrl,
            data: data,
            action: action
        )
    }
}
