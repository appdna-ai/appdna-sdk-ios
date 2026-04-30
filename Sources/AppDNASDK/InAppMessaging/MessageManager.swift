import Foundation
import UIKit
import SwiftUI

/// Manages in-app message trigger evaluation, frequency tracking, and presentation.
final class MessageManager {
    private let remoteConfigManager: RemoteConfigManager
    private let eventTracker: EventTracker
    private let frequencyTracker = MessageFrequencyTracker()
    private var isPresenting = false

    /// When true, suppresses display of in-app messages.
    var suppressDisplay = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(remoteConfigManager: RemoteConfigManager, eventTracker: EventTracker) {
        self.remoteConfigManager = remoteConfigManager
        self.eventTracker = eventTracker
    }

    /// Evaluate all active messages against an event. Called internally after every track() call.
    func onEvent(eventName: String, properties: [String: Any]?) {
        guard !isPresenting, !suppressDisplay else {
            Log.debug("[Messages] Skipping event '\(eventName)' — isPresenting=\(isPresenting), suppressDisplay=\(suppressDisplay)")
            return
        }

        let messages = remoteConfigManager.getActiveMessages()
        Log.debug("[Messages] Evaluating \(messages.count) active message(s) for event '\(eventName)'")
        var candidates: [(id: String, config: MessageConfig)] = []
        var filteredByEvent = 0
        var filteredByConditions = 0
        var filteredByFrequency = 0
        var filteredByDateRange = 0

        for (id, config) in messages {
            // 1. Event name match
            guard config.trigger_rules?.event == eventName else {
                filteredByEvent += 1
                continue
            }

            // 2. Conditions evaluation
            guard evaluateConditions(config.trigger_rules?.conditions, properties: properties ?? [:]) else {
                filteredByConditions += 1
                continue
            }

            // 3. Frequency check
            guard frequencyTracker.canShow(
                messageId: id,
                frequency: config.trigger_rules?.frequency ?? .once,
                maxDisplays: config.trigger_rules?.max_displays
            ) else {
                filteredByFrequency += 1
                continue
            }

            // 4. Date range check
            guard checkDateRange(config) else {
                filteredByDateRange += 1
                continue
            }

            candidates.append((id: id, config: config))
        }

        if candidates.isEmpty {
            Log.debug("[Messages] No candidates for '\(eventName)' — filtered: event=\(filteredByEvent), conditions=\(filteredByConditions), frequency=\(filteredByFrequency), dateRange=\(filteredByDateRange)")
        } else {
            Log.debug("[Messages] \(candidates.count) candidate(s) passed all filters for '\(eventName)'")
        }

        // 5. Sort by priority (highest first)
        guard let winner = candidates.sorted(by: { ($0.config.priority ?? 0) > ($1.config.priority ?? 0) }).first else {
            return
        }

        // 6. Present with optional delay
        let delay = winner.config.trigger_rules?.delay_seconds ?? 0
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) { [weak self] in
                self?.present(messageId: winner.id, config: winner.config, triggerEvent: eventName)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.present(messageId: winner.id, config: winner.config, triggerEvent: eventName)
            }
        }
    }

    /// Reset session-level frequency tracking.
    func resetSession() {
        frequencyTracker.resetSession()
    }

    // MARK: - Presentation

    private func present(messageId: String, config: MessageConfig, triggerEvent: String) {
        guard !isPresenting else { return }

        // SPEC-400 — `shouldShowMessage` veto. Run BEFORE any analytics
        // tracking or view construction so a vetoed message produces no
        // `in_app_message_shown` event. The protocol's default extension
        // returns `true`, so hosts that don't implement this method are
        // unaffected. Reading the delegate fresh on every call.
        if let host = AppDNA.inAppMessages.delegate, host.shouldShowMessage(messageId: messageId) == false {
            Log.debug("In-app message \(messageId) suppressed by host shouldShowMessage veto")
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            Log.warning("No root view controller available for in-app message")
            return
        }

        // Find topmost presented VC
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        isPresenting = true
        frequencyTracker.recordShown(messageId: messageId, frequency: config.trigger_rules?.frequency ?? .once)

        // Track shown
        eventTracker.track(event: "in_app_message_shown", properties: [
            "message_id": messageId,
            "message_type": config.message_type?.rawValue ?? "modal",
            "trigger_event": triggerEvent,
        ])

        // SPEC-400 — fire onMessageShown to the host's registered
        // delegate alongside the existing analytics track.
        DispatchQueue.main.async {
            AppDNA.inAppMessages.delegate?.onMessageShown(messageId: messageId, trigger: triggerEvent)
        }

        let messageView = MessageRenderer(
            messageId: messageId,
            config: config,
            onCTATap: { [weak self] in
                self?.eventTracker.track(event: "in_app_message_clicked", properties: [
                    "message_id": messageId,
                    "cta_action": config.content?.cta_action?.type?.rawValue ?? "dismiss",
                ])
                // SPEC-400 — fire onMessageAction with action type + cta_action data.
                let ctaActionType = config.content?.cta_action?.type?.rawValue ?? "dismiss"
                let ctaData: [String: Any]? = {
                    guard let cta = config.content?.cta_action, let url = cta.url else { return nil }
                    return ["url": url]
                }()
                DispatchQueue.main.async {
                    AppDNA.inAppMessages.delegate?.onMessageAction(messageId: messageId, action: ctaActionType, data: ctaData)
                }
                self?.handleCTAAction(config.content?.cta_action)
                topVC.dismiss(animated: true) {
                    self?.isPresenting = false
                    DispatchQueue.main.async {
                        AppDNA.inAppMessages.delegate?.onMessageDismissed(messageId: messageId)
                    }
                }
            },
            onDismiss: { [weak self] in
                self?.eventTracker.track(event: "in_app_message_dismissed", properties: [
                    "message_id": messageId,
                ])
                topVC.dismiss(animated: true) {
                    self?.isPresenting = false
                    // SPEC-400 — fire onMessageDismissed.
                    DispatchQueue.main.async {
                        AppDNA.inAppMessages.delegate?.onMessageDismissed(messageId: messageId)
                    }
                }
            }
        )

        let hostingVC = UIHostingController(rootView: messageView)
        hostingVC.modalPresentationStyle = config.message_type == .fullscreen ? .fullScreen : .overCurrentContext
        hostingVC.modalTransitionStyle = .crossDissolve
        hostingVC.view.backgroundColor = .clear
        topVC.present(hostingVC, animated: true)
    }

    // MARK: - Condition evaluation

    private func evaluateConditions(_ conditions: [TriggerCondition]?, properties: [String: Any]) -> Bool {
        guard let conditions, !conditions.isEmpty else { return true }

        return conditions.allSatisfy { condition in
            guard let field = condition.field, let propValue = properties[field] else { return false }
            guard let op = condition.`operator` else { return false }
            guard let condValue = condition.value?.value else { return false }
            return evaluateOperator(op, propValue: propValue, condValue: condValue)
        }
    }

    private func evaluateOperator(_ op: TriggerCondition.ConditionOperator, propValue: Any, condValue: Any) -> Bool {
        switch op {
        case .eq:
            return "\(propValue)" == "\(condValue)"
        case .gte:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum >= cNum
        case .lte:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum <= cNum
        case .gt:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum > cNum
        case .lt:
            guard let pNum = toDouble(propValue), let cNum = toDouble(condValue) else { return false }
            return pNum < cNum
        case .contains:
            return "\(propValue)".contains("\(condValue)")
        }
    }

    private func toDouble(_ value: Any) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    // MARK: - Date range

    private func checkDateRange(_ config: MessageConfig) -> Bool {
        let now = Date()
        if let startStr = config.start_date,
           let start = Self.dateFormatter.date(from: startStr),
           now < start {
            return false
        }
        if let endStr = config.end_date,
           let end = Self.dateFormatter.date(from: endStr),
           now > end {
            return false
        }
        return true
    }

    // MARK: - CTA actions

    private func handleCTAAction(_ action: CTAAction?) {
        guard let action, let actionType = action.type else { return }
        switch actionType {
        case .dismiss, .unknown:
            break // dismiss handled by caller
        case .deep_link, .open_url:
            if let urlString = action.url, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}
