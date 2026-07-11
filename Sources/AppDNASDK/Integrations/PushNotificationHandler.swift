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

        // SPEC-089c: Auto-show server-driven screen from push action (AC-076).
        // When a BUTTON was tapped, route on that button's own action — routing every button tap
        // through the body action would send every button to the same destination.
        let routed = payload.actions.first { $0.id == tappedAction } ?? payload.action
        if let routed, routed.type == "show_screen" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AppDNA.showScreen(routed.value)
            }
        }

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
        PushPayloadParser.parse(userInfo: content.userInfo, title: content.title, body: content.body)
    }
}

// MARK: - Push payload parsing

/// Turns a raw APNs `userInfo` dictionary into the `PushPayload` handed to the host.
///
/// Extracted from `PushNotificationHandler.buildPayload` and stripped of its `UNNotificationContent`
/// dependency: the only two things it needed from the content are the title and body strings, and
/// `UNNotificationContent` cannot be constructed with a payload in a unit test — which is why the
/// `actions` array was shipped by the server, registered as buttons, and then silently dropped on the
/// way to the host without any test noticing.
enum PushPayloadParser {
    static func parse(userInfo: [AnyHashable: Any], title: String, body: String) -> PushPayload {
        let pushId = userInfo["push_id"] as? String ?? ""
        let imageUrl = userInfo["image_url"] as? String
        let data = userInfo["data"] as? [String: Any]

        // SPEC-088: Interpolate push title, body, and action button labels via TemplateEngine.
        let ctx = TemplateEngine.shared.buildContext()

        var actions: [PushAction] = []
        for entry in userInfo["actions"] as? [[String: Any]] ?? [] {
            guard let type = entry["action_type"] as? String else { continue }
            let rawLabel = entry["label"] as? String
            actions.append(PushAction(
                type: type,
                // "dismiss" and friends carry no target — an absent value is not a malformed button.
                value: entry["action_value"] as? String ?? "",
                id: entry["id"] as? String,
                label: rawLabel.map { TemplateEngine.shared.interpolate($0, context: ctx) }
            ))
        }

        // The notification-body tap action. Falls back to the first button so hosts reading the
        // pre-existing single `action` field keep working on payloads that only carry `actions`.
        var action: PushAction? = nil
        if let actionData = userInfo["action"] as? [String: String],
           let type = actionData["type"], let value = actionData["value"] {
            action = PushAction(type: type, value: value)
        }

        return PushPayload(
            pushId: pushId,
            title: TemplateEngine.shared.interpolate(title, context: ctx),
            body: TemplateEngine.shared.interpolate(body, context: ctx),
            imageUrl: imageUrl,
            data: data,
            action: action ?? actions.first,
            actions: actions
        )
    }
}
