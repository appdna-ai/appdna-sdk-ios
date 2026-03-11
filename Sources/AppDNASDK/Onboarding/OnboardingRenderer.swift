import SwiftUI

/// Top-level SwiftUI host that manages onboarding flow state and step navigation.
struct OnboardingFlowHost: View {
    let flow: OnboardingFlowConfig
    weak var delegate: AppDNAOnboardingDelegate?
    let onStepViewed: (_ stepId: String, _ stepIndex: Int) -> Void
    let onStepCompleted: (_ stepId: String, _ stepIndex: Int, _ data: [String: Any]?) -> Void
    let onStepSkipped: (_ stepId: String, _ stepIndex: Int) -> Void
    let onFlowCompleted: (_ responses: [String: Any]) -> Void
    let onFlowDismissed: (_ lastStepId: String, _ lastStepIndex: Int) -> Void

    @State private var currentIndex = 0
    @State private var responses: [String: Any] = [:]

    // SPEC-083: Hook state
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var configOverrides: [String: StepConfigOverride] = [:]

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
                    let effectiveConfig = applyOverrides(to: step.config, stepId: step.id)

                    ZStack {
                        OnboardingStepRouter(
                            step: step,
                            effectiveConfig: effectiveConfig,
                            onNext: { data in
                                handleStepCompleted(step: step, data: data)
                            },
                            onSkip: {
                                handleStepSkipped(step: step)
                            }
                        )
                        .id(currentIndex)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))

                        // SPEC-083: Error banner
                        if showError, let msg = errorMessage {
                            VStack {
                                errorBanner(message: msg)
                                Spacer()
                            }
                        }

                        // SPEC-083: Loading overlay
                        if isProcessing {
                            loadingOverlay
                        }
                    }
                    .onAppear {
                        handleStepAppear(step: step)
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
                .disabled(isProcessing)
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
            .disabled(isProcessing)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - SPEC-083: Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                Text("Processing...")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color.black.opacity(0.7))
            .cornerRadius(16)
        }
    }

    // MARK: - SPEC-083: Error banner

    private func errorBanner(message: String) -> some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Spacer()

            Button {
                withAnimation { showError = false; errorMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red)
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { showError = false; errorMessage = nil }
            }
        }
    }

    // MARK: - Config overrides (SPEC-083)

    private func applyOverrides(to config: StepConfig, stepId: String) -> StepConfig {
        guard let override = configOverrides[stepId] else { return config }
        let fieldDefaults = override.fieldDefaults?.mapValues { AnyCodable($0) }
        return StepConfig(
            title: override.title ?? config.title,
            subtitle: override.subtitle ?? config.subtitle,
            image_url: config.image_url,
            cta_text: override.ctaText ?? config.cta_text,
            skip_enabled: config.skip_enabled,
            options: config.options,
            selection_mode: config.selection_mode,
            items: config.items,
            layout: config.layout,
            fields: config.fields,
            validation_mode: config.validation_mode,
            field_defaults: fieldDefaults
        )
    }

    // MARK: - Step lifecycle

    private func handleStepAppear(step: OnboardingStep) {
        Task {
            if let override = await delegate?.onBeforeStepRender(
                flowId: flow.id,
                stepId: step.id,
                stepIndex: currentIndex,
                stepType: step.type.rawValue,
                responses: responses
            ) {
                await MainActor.run {
                    configOverrides[step.id] = override
                }
            }
            await MainActor.run {
                onStepViewed(step.id, currentIndex)
            }
        }
    }

    private func handleStepCompleted(step: OnboardingStep, data: [String: Any]?) {
        if let data {
            responses[step.id] = data
        }
        onStepCompleted(step.id, currentIndex, data)

        // SPEC-083: Call async hook before advancing
        isProcessing = true
        Task {
            let result = await delegate?.onBeforeStepAdvance(
                flowId: flow.id,
                fromStepId: step.id,
                stepIndex: currentIndex,
                stepType: step.type.rawValue,
                responses: responses,
                stepData: data
            ) ?? .proceed

            await MainActor.run {
                isProcessing = false

                switch result {
                case .proceed:
                    advanceOrComplete()

                case .proceedWithData(let extraData):
                    mergeData(extraData, forStepId: step.id)
                    advanceOrComplete()

                case .block(let message):
                    errorMessage = message
                    withAnimation { showError = true }

                case .skipTo(let targetStepId):
                    skipToStep(targetStepId)

                case .skipToWithData(let targetStepId, let extraData):
                    mergeData(extraData, forStepId: step.id)
                    skipToStep(targetStepId)
                }
            }
        }
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

    private func skipToStep(_ targetStepId: String) {
        guard let targetIndex = flow.steps.firstIndex(where: { $0.id == targetStepId }) else {
            advanceOrComplete()
            return
        }
        withAnimation { currentIndex = targetIndex }
    }

    private func mergeData(_ extraData: [String: Any], forStepId stepId: String) {
        if var existing = responses[stepId] as? [String: Any] {
            existing.merge(extraData) { _, new in new }
            responses[stepId] = existing
        } else {
            responses[stepId] = extraData
        }
    }
}

// MARK: - Step router

/// Routes to the appropriate step view based on step type.
struct OnboardingStepRouter: View {
    let step: OnboardingStep
    let effectiveConfig: StepConfig
    let onNext: ([String: Any]?) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack {
            switch step.type {
            case .welcome:
                WelcomeStepView(config: effectiveConfig, onNext: { onNext(nil) })
            case .question:
                QuestionStepView(config: effectiveConfig, onNext: onNext)
            case .value_prop:
                ValuePropStepView(config: effectiveConfig, onNext: { onNext(nil) })
            case .custom:
                CustomStepView(config: effectiveConfig, onNext: { onNext(nil) })
            case .form:
                FormStepView(config: effectiveConfig, onNext: onNext)
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
