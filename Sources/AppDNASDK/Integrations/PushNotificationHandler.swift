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

        // SPEC-088: Interpolate action button labels
        let pushCtx = TemplateEngine.shared.buildContext()
        let actions: [UNNotificationAction] = actionsData.compactMap { actionData in
            guard let id = actionData["id"] as? String,
                  let rawLabel = actionData["label"] as? String else { return nil }
            let label = TemplateEngine.shared.interpolate(rawLabel, context: pushCtx)
            let foreground = actionData["foreground"] as? Bool ?? false
            let options: UNNotificationActionOptions = foreground ? [.foreground] : []

            // SPEC-085: Action button icon support (iOS 15+)
            if #available(iOS 15.0, *) {
                if let iconData = actionData["icon"] as? [String: Any],
                   let iconLib = iconData["library"] as? String,
                   let iconName = iconData["name"] as? String {
                    let sfSymbolName: String
                    if iconLib == "sf-symbols" {
                        sfSymbolName = iconName
                    } else if iconLib == "lucide", let mapped = IconMapping.lucideToSFSymbol[iconName] {
                        sfSymbolName = mapped
                    } else if iconLib == "material", let mapped = IconMapping.materialToSFSymbol[iconName] {
                        sfSymbolName = mapped
                    } else {
                        sfSymbolName = iconName
                    }
                    let icon = UNNotificationActionIcon(systemImageName: sfSymbolName)
                    return UNNotificationAction(identifier: id, title: label, options: options, icon: icon)
                }
            }
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

        // SPEC-088: Interpolate push title and body via TemplateEngine
        let ctx = TemplateEngine.shared.buildContext()
        let interpolatedTitle = TemplateEngine.shared.interpolate(content.title, context: ctx)
        let interpolatedBody = TemplateEngine.shared.interpolate(content.body, context: ctx)

        return PushPayload(
            pushId: pushId,
            title: interpolatedTitle,
            body: interpolatedBody,
            imageUrl: imageUrl,
            data: data,
            action: action
        )
    }
}
