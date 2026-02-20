import SwiftUI

/// Top-level SwiftUI host that manages onboarding flow state and step navigation.
struct OnboardingFlowHost: View {
    let flow: OnboardingFlowConfig
    let onStepViewed: (_ stepId: String, _ stepIndex: Int) -> Void
    let onStepCompleted: (_ stepId: String, _ stepIndex: Int, _ data: [String: Any]?) -> Void
    let onStepSkipped: (_ stepId: String, _ stepIndex: Int) -> Void
    let onFlowCompleted: (_ responses: [String: Any]) -> Void
    let onFlowDismissed: (_ lastStepId: String, _ lastStepIndex: Int) -> Void

    @State private var currentIndex = 0
    @State private var responses: [String: Any] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                if flow.settings.show_progress {
                    progressBar
                }

                // Navigation bar
                navigationBar

                // Step content
                if currentIndex < flow.steps.count {
                    let step = flow.steps[currentIndex]
                    OnboardingStepRouter(
                        step: step,
                        onNext: { data in
                            handleStepCompleted(step: step, data: data)
                        },
                        onSkip: {
                            handleStepSkipped(step: step)
                        }
                    )
                    .id(currentIndex) // Force recreation on index change
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                    .onAppear {
                        onStepViewed(step.id, currentIndex)
                    }
                }
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentIndex)
            }
        }
        .frame(height: 4)
    }

    private var progress: CGFloat {
        guard flow.steps.count > 0 else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(flow.steps.count)
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if flow.settings.allow_back && currentIndex > 0 {
                Button {
                    withAnimation { currentIndex -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            // Dismiss button
            Button {
                let step = flow.steps[currentIndex]
                onFlowDismissed(step.id, currentIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Step lifecycle

    private func handleStepCompleted(step: OnboardingStep, data: [String: Any]?) {
        if let data {
            responses[step.id] = data
        }
        onStepCompleted(step.id, currentIndex, data)
        advanceOrComplete()
    }

    private func handleStepSkipped(step: OnboardingStep) {
        onStepSkipped(step.id, currentIndex)
        advanceOrComplete()
    }

    private func advanceOrComplete() {
        if currentIndex + 1 >= flow.steps.count {
            onFlowCompleted(responses)
        } else {
            withAnimation { currentIndex += 1 }
        }
    }
}

// MARK: - Step router

/// Routes to the appropriate step view based on step type.
struct OnboardingStepRouter: View {
    let step: OnboardingStep
    let onNext: ([String: Any]?) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack {
            switch step.type {
            case .welcome:
                WelcomeStepView(config: step.config, onNext: { onNext(nil) })
            case .question:
                QuestionStepView(config: step.config, onNext: onNext)
            case .value_prop:
                ValuePropStepView(config: step.config, onNext: { onNext(nil) })
            case .custom:
                CustomStepView(config: step.config, onNext: { onNext(nil) })
            }

            if step.config.skip_enabled == true {
                Button("Skip") { onSkip() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
        }
    }
}
