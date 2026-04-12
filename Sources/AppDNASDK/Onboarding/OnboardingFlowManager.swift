import Foundation
import UIKit
import SwiftUI

/// Manages onboarding flow presentation, state, and event tracking.
final class OnboardingFlowManager {
    private let remoteConfigManager: RemoteConfigManager
    private let eventTracker: EventTracker

    init(remoteConfigManager: RemoteConfigManager, eventTracker: EventTracker) {
        self.remoteConfigManager = remoteConfigManager
        self.eventTracker = eventTracker
    }

    /// Present an onboarding flow. Returns false if config is unavailable.
    @discardableResult
    func present(
        flowId: String?,
        from viewController: UIViewController,
        delegate: AppDNAOnboardingDelegate?
    ) -> Bool {
        // Resolve flow config
        guard let flow = resolveFlow(flowId: flowId) else {
            Log.warning("Onboarding flow not found — flowId: \(flowId ?? "active")")
            return false
        }

        // Track flow started
        eventTracker.track(event: "onboarding_flow_started", properties: [
            "flow_id": flow.id,
            "flow_version": flow.version,
        ])

        // Kick off image prefetch for the first step immediately — by the time
        // the hosting controller's view appears a few hundred ms later, the
        // URL cache is warm and the background image renders synchronously
        // with no placeholder flash.
        if let firstStep = flow.steps.first {
            let urls = OnboardingFlowHost.collectImageURLs(from: firstStep)
            if !urls.isEmpty {
                ImagePreloader.prefetch(urls: urls, timeout: 3.0) { }
            }
        }

        let startTime = Date()

        // Build the SwiftUI view with state
        let rendererView = OnboardingFlowHost(
            flow: flow,
            delegate: delegate,
            eventTracker: eventTracker,
            onStepViewed: { [weak self] stepId, stepIndex in
                self?.eventTracker.track(event: "onboarding_step_viewed", properties: [
                    "flow_id": flow.id,
                    "step_id": stepId,
                    "step_index": stepIndex,
                    "step_type": flow.steps[stepIndex].type.rawValue,
                ])
                delegate?.onOnboardingStepChanged(flowId: flow.id, stepId: stepId, stepIndex: stepIndex, totalSteps: flow.steps.count)
            },
            onStepCompleted: { [weak self] stepId, stepIndex, data in
                self?.eventTracker.track(event: "onboarding_step_completed", properties: [
                    "flow_id": flow.id,
                    "step_id": stepId,
                    "step_index": stepIndex,
                    "selection_data": data ?? [:],
                ])
                // Step completion tracked via event above
            },
            onStepSkipped: { [weak self] stepId, stepIndex in
                self?.eventTracker.track(event: "onboarding_step_skipped", properties: [
                    "flow_id": flow.id,
                    "step_id": stepId,
                    "step_index": stepIndex,
                ])
                // Step skip tracked via event above
            },
            onFlowCompleted: { [weak self] responses in
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                self?.eventTracker.track(event: "onboarding_flow_completed", properties: [
                    "flow_id": flow.id,
                    "total_steps": flow.steps.count,
                    "total_duration_ms": durationMs,
                    "responses": responses,
                ])
                // SPEC-088: Persist onboarding responses for cross-module access
                SessionDataStore.shared.setOnboardingResponses(responses)
                delegate?.onOnboardingCompleted(flowId: flow.id, responses: responses)
                viewController.dismiss(animated: true)
            },
            onFlowDismissed: { [weak self] lastStepId, lastStepIndex in
                self?.eventTracker.track(event: "onboarding_flow_dismissed", properties: [
                    "flow_id": flow.id,
                    "last_step_id": lastStepId,
                    "last_step_index": lastStepIndex,
                ])
                delegate?.onOnboardingDismissed(flowId: flow.id, atStep: lastStepIndex)
                viewController.dismiss(animated: true)
            }
        )

        let hostingController = UIHostingController(rootView: rendererView)
        hostingController.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        viewController.present(hostingController, animated: true)
        return true
    }

    // MARK: - Private

    private func resolveFlow(flowId: String?) -> OnboardingFlowConfig? {
        // If explicit flowId, use it directly
        if let flowId {
            return remoteConfigManager.getOnboardingFlow(id: flowId)
        }

        // Try audience-based selection: evaluate all flows, pick highest priority match
        let userTraits = AppDNA.getUserTraits()
        if !userTraits.isEmpty {
            let allFlows = remoteConfigManager.getAllOnboardingFlows()
            let matching = allFlows.values
                .filter { flow in
                    guard flow.audience_rules != nil else { return false }
                    return AudienceRuleEvaluator.evaluate(rules: flow.audience_rules, traits: userTraits)
                }
                .sorted {
                    let p0 = ($0.audience_rules?.value as? [String: Any])?["priority"] as? Int ?? 0
                    let p1 = ($1.audience_rules?.value as? [String: Any])?["priority"] as? Int ?? 0
                    return p0 > p1
                }

            if let bestMatch = matching.first {
                let priority = (bestMatch.audience_rules?.value as? [String: Any])?["priority"] as? Int ?? 0
                Log.info("[Onboarding] Audience-matched flow: \(bestMatch.id) (priority: \(priority))")
                return bestMatch
            }
        }

        // Fallback: active flow
        return remoteConfigManager.getOnboardingFlow(id: nil)
    }
}
