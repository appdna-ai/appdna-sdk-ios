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

        let startTime = Date()

        // Build the SwiftUI view with state
        let rendererView = OnboardingFlowHost(
            flow: flow,
            onStepViewed: { [weak self] stepId, stepIndex in
                self?.eventTracker.track(event: "onboarding_step_viewed", properties: [
                    "flow_id": flow.id,
                    "step_id": stepId,
                    "step_index": stepIndex,
                    "step_type": flow.steps[stepIndex].type.rawValue,
                ])
                delegate?.onboardingStepViewed(flowId: flow.id, stepId: stepId, stepIndex: stepIndex)
            },
            onStepCompleted: { [weak self] stepId, stepIndex, data in
                self?.eventTracker.track(event: "onboarding_step_completed", properties: [
                    "flow_id": flow.id,
                    "step_id": stepId,
                    "step_index": stepIndex,
                    "selection_data": data ?? [:],
                ])
                delegate?.onboardingStepCompleted(flowId: flow.id, stepId: stepId, data: data)
            },
            onStepSkipped: { [weak self] stepId, stepIndex in
                self?.eventTracker.track(event: "onboarding_step_skipped", properties: [
                    "flow_id": flow.id,
                    "step_id": stepId,
                    "step_index": stepIndex,
                ])
                delegate?.onboardingStepSkipped(flowId: flow.id, stepId: stepId)
            },
            onFlowCompleted: { [weak self] responses in
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                self?.eventTracker.track(event: "onboarding_flow_completed", properties: [
                    "flow_id": flow.id,
                    "total_steps": flow.steps.count,
                    "total_duration_ms": durationMs,
                    "responses": responses,
                ])
                delegate?.onboardingFlowCompleted(flowId: flow.id, data: responses)
                viewController.dismiss(animated: true)
            },
            onFlowDismissed: { [weak self] lastStepId, lastStepIndex in
                self?.eventTracker.track(event: "onboarding_flow_dismissed", properties: [
                    "flow_id": flow.id,
                    "last_step_id": lastStepId,
                    "last_step_index": lastStepIndex,
                ])
                delegate?.onboardingFlowDismissed(flowId: flow.id, lastStepId: lastStepId)
                viewController.dismiss(animated: true)
            }
        )

        let hostingController = UIHostingController(rootView: rendererView)
        hostingController.modalPresentationStyle = .fullScreen
        viewController.present(hostingController, animated: true)
        return true
    }

    // MARK: - Private

    private func resolveFlow(flowId: String?) -> OnboardingFlowConfig? {
        return remoteConfigManager.getOnboardingFlow(id: flowId)
    }
}
