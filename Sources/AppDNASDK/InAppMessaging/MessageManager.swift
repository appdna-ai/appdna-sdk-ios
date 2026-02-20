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
        guard !isPresenting, !suppressDisplay else { return }

        let messages = remoteConfigManager.getActiveMessages()
        var candidates: [(id: String, config: MessageConfig)] = []

        for (id, config) in messages {
            // 1. Event name match
            guard config.trigger_rules.event == eventName else { continue }

            // 2. Conditions evaluation
            guard evaluateConditions(config.trigger_rules.conditions, properties: properties ?? [:]) else { continue }

            // 3. Frequency check
            guard frequencyTracker.canShow(
                messageId: id,
                frequency: config.trigger_rules.frequency,
                maxDisplays: config.trigger_rules.max_displays
            ) else { continue }

            // 4. Date range check
            guard checkDateRange(config) else { continue }

            candidates.append((id: id, config: config))
        }

        // 5. Sort by priority (highest first)
        guard let winner = candidates.sorted(by: { $0.config.priority > $1.config.priority }).first else {
            return
        }

        // 6. Present with optional delay
        let delay = winner.config.trigger_rules.delay_seconds ?? 0
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
        frequencyTracker.recordShown(messageId: messageId, frequency: config.trigger_rules.frequency)

        // Track shown
        eventTracker.track(event: "in_app_message_shown", properties: [
            "message_id": messageId,
            "message_type": config.message_type.rawValue,
            "trigger_event": triggerEvent,
        ])

        let messageView = MessageRenderer(
            messageId: messageId,
            config: config,
            onCTATap: { [weak self] in
                self?.eventTracker.track(event: "in_app_message_clicked", properties: [
                    "message_id": messageId,
                    "cta_action": config.content.cta_action?.type.rawValue ?? "dismiss",
                ])
                self?.handleCTAAction(config.content.cta_action)
                topVC.dismiss(animated: true) {
                    self?.isPresenting = false
                }
            },
            onDismiss: { [weak self] in
                self?.eventTracker.track(event: "in_app_message_dismissed", properties: [
                    "message_id": messageId,
                ])
                topVC.dismiss(animated: true) {
                    self?.isPresenting = false
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
            guard let propValue = properties[condition.field] else { return false }
            return evaluateOperator(condition.operator, propValue: propValue, condValue: condition.value.value)
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
        guard let action else { return }
        switch action.type {
        case .dismiss:
            break // dismiss handled by caller
        case .deep_link, .open_url:
            if let urlString = action.url, let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }
    }
}
