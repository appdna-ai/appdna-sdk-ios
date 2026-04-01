import SwiftUI

/// Top-level SwiftUI host that manages onboarding flow state and step navigation.
struct OnboardingFlowHost: View {
    let flow: OnboardingFlowConfig
    weak var delegate: AppDNAOnboardingDelegate?
    let eventTracker: EventTracker?
    let onStepViewed: (_ stepId: String, _ stepIndex: Int) -> Void
    let onStepCompleted: (_ stepId: String, _ stepIndex: Int, _ data: [String: Any]?) -> Void
    let onStepSkipped: (_ stepId: String, _ stepIndex: Int) -> Void
    let onFlowCompleted: (_ responses: [String: Any]) -> Void
    let onFlowDismissed: (_ lastStepId: String, _ lastStepIndex: Int) -> Void

    @State private var currentIndex = 0
    @State private var responses: [String: Any] = [:]

    // SPEC-083: Hook state
    @State private var isProcessing = false
    @State private var loadingText: String = "Processing..."
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var configOverrides: [String: StepConfigOverride] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (hidden per-step via hide_progress while still counting in total)
                if flow.settings.show_progress && !(currentIndex < flow.steps.count && flow.steps[currentIndex].hide_progress == true) {
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
                            },
                            flowId: flow.id,
                            currentStepIndex: currentIndex,
                            totalSteps: flow.steps.count
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

    @ViewBuilder
    private var progressBar: some View {
        let trackColor: Color = {
            if let hex = flow.settings.progress_track_color { return Color(hex: hex) }
            return Color.gray.opacity(0.2)
        }()
        let fillColor: Color = {
            if let hex = flow.settings.progress_color { return Color(hex: hex) }
            return Color(hex: "#6366F1")
        }()
        let style = flow.settings.progress_style ?? "continuous_bar"
        let total = flow.steps.count
        let current = currentIndex

        switch style {
        case "dots":
            HStack(spacing: 8) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i <= current ? fillColor : trackColor)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
            .frame(height: 12)
            .padding(.horizontal)

        case "segmented_bar":
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= current ? fillColor : trackColor)
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)

        case "fraction":
            Text("\(current + 1)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(fillColor)
                .frame(height: 16)

        case "none":
            EmptyView()

        default: // continuous_bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(trackColor)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)
        }
    }

    private var progress: CGFloat {
        guard flow.steps.count > 0 else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(flow.steps.count)
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        let backStyle = flow.settings.back_button_style
        let backSize = backStyle?.icon_size ?? 16
        let backColor: Color = backStyle?.icon_color.flatMap { Color(hex: $0) } ?? Color(hex: "#6B7280")

        return HStack {
            if flow.settings.allow_back && currentIndex > 0 {
                Button {
                    withAnimation { currentIndex -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: backSize, weight: .semibold))
                        .foregroundColor(backColor)
                        .frame(width: 44, height: 44)
                }
                .disabled(isProcessing)
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            // Dismiss button
            if flow.settings.dismiss_allowed ?? true {
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

                Text(loadingText)
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
            field_defaults: fieldDefaults,
            content_blocks: config.content_blocks,
            layout_variant: config.layout_variant,
            background: config.background,
            text_style: config.text_style,
            element_style: config.element_style,
            animation: config.animation,
            localizations: config.localizations,
            default_locale: config.default_locale
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
        // SPEC-087: Persist responses incrementally so TemplateEngine has fresh data for next step
        SessionDataStore.shared.setOnboardingResponses(responses)
        onStepCompleted(step.id, currentIndex, data)

        // SPEC-083: Determine hook type — client delegate takes priority over server hook
        if delegate != nil {
            // Client-side hook
            executeClientHook(step: step, data: data)
        } else if let hook = step.hook, hook.enabled == true {
            // Server-side hook (P1)
            executeServerHook(step: step, data: data, hookConfig: hook)
        } else {
            // No hook — advance immediately
            advanceOrComplete()
        }
    }

    // MARK: - Client-side hook execution

    private func executeClientHook(step: OnboardingStep, data: [String: Any]?) {
        loadingText = step.hook?.loading_text ?? "Processing..."

        let startTime = Date()
        trackHookEvent("onboarding_hook_started", step: step, extra: ["hook_type": "client"])

        // Only show loading after a delay — avoids flash for instant responses
        let showLoadingTimer = DispatchWorkItem { [self] in
            isProcessing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: showLoadingTimer)

        Task {
            let result = await delegate?.onBeforeStepAdvance(
                flowId: flow.id,
                fromStepId: step.id,
                stepIndex: currentIndex,
                stepType: step.type.rawValue,
                responses: responses,
                stepData: data
            ) ?? .proceed

            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            await MainActor.run {
                showLoadingTimer.cancel()
                isProcessing = false
                trackHookEvent("onboarding_hook_completed", step: step, extra: [
                    "hook_type": "client",
                    "result": resultName(result),
                    "duration_ms": durationMs,
                ])
                handleHookResult(result, step: step)
            }
        }
    }

    // MARK: - Server-side hook execution (P1)

    private func executeServerHook(step: OnboardingStep, data: [String: Any]?, hookConfig: StepHookConfig) {
        loadingText = hookConfig.loading_text ?? "Processing..."
        isProcessing = true

        trackHookEvent("onboarding_hook_started", step: step, extra: [
            "hook_type": "server",
            "webhook_url": hookConfig.webhook_url,
        ])

        let startTime = Date()

        Task {
            let result = await executeWebhook(
                step: step,
                data: data,
                hookConfig: hookConfig,
                attempt: 0
            )

            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            await MainActor.run {
                isProcessing = false
                trackHookEvent("onboarding_hook_completed", step: step, extra: [
                    "hook_type": "server",
                    "result": resultName(result),
                    "duration_ms": durationMs,
                ])
                handleHookResult(result, step: step)
            }
        }
    }

    private func executeWebhook(
        step: OnboardingStep,
        data: [String: Any]?,
        hookConfig: StepHookConfig,
        attempt: Int
    ) async -> StepAdvanceResult {
        guard let webhookUrl = hookConfig.webhook_url, let url = URL(string: webhookUrl) else {
            return .block(message: hookConfig.error_text ?? "Invalid webhook URL.")
        }

        // Build request body
        let body: [String: Any] = [
            "flow_id": flow.id,
            "step_id": step.id,
            "step_index": currentIndex,
            "step_type": step.type.rawValue,
            "step_data": data ?? [:],
            "responses": responses,
            "user_id": AppDNA.currentUserId ?? "",
            "app_id": AppDNA.currentAppId ?? "",
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(hookConfig.timeout_ms ?? 10000) / 1000.0

        // Apply custom headers with variable interpolation
        if let headers = hookConfig.headers {
            for (key, value) in headers {
                let resolved = interpolateVariables(value)
                request.setValue(resolved, forHTTPHeaderField: key)
            }
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = TimeInterval(hookConfig.timeout_ms ?? 10000) / 1000.0
            let session = URLSession(configuration: config)

            let (responseData, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw APIError.httpError(
                    statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    data: nil
                )
            }

            return parseWebhookResponse(responseData, hookConfig: hookConfig)

        } catch let error as URLError where error.code == .timedOut {
            // Timeout — retry or block
            let maxRetries = min(hookConfig.retry_count ?? 0, 3)
            if attempt < maxRetries {
                trackHookEvent("onboarding_hook_retry", step: step, extra: [
                    "attempt_number": attempt + 1,
                ])
                let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return await executeWebhook(step: step, data: data, hookConfig: hookConfig, attempt: attempt + 1)
            }
            trackHookEvent("onboarding_hook_error", step: step, extra: [
                "hook_type": "server",
                "error_type": "timeout",
                "error_message": "Request timed out",
            ])
            return .block(message: hookConfig.error_text ?? "Request timed out. Please try again.")

        } catch {
            // Network error — retry or block
            let maxRetries = min(hookConfig.retry_count ?? 0, 3)
            if attempt < maxRetries {
                trackHookEvent("onboarding_hook_retry", step: step, extra: [
                    "attempt_number": attempt + 1,
                ])
                let delay = pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return await executeWebhook(step: step, data: data, hookConfig: hookConfig, attempt: attempt + 1)
            }
            trackHookEvent("onboarding_hook_error", step: step, extra: [
                "hook_type": "server",
                "error_type": "network",
                "error_message": error.localizedDescription,
            ])
            return .block(message: hookConfig.error_text ?? "Network error. Please check your connection.")
        }
    }

    private func parseWebhookResponse(_ data: Data, hookConfig: StepHookConfig) -> StepAdvanceResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return .block(message: hookConfig.error_text ?? "Invalid server response.")
        }

        let responseData = json["data"] as? [String: Any]
        let message = json["message"] as? String
        let targetStepId = json["target_step_id"] as? String

        switch action {
        case "proceed":
            if let responseData {
                return .proceedWithData(responseData)
            }
            return .proceed

        case "proceed_with_data":
            return .proceedWithData(responseData ?? [:])

        case "block":
            return .block(message: message ?? hookConfig.error_text ?? "Request blocked by server.")

        case "skip_to":
            guard let targetStepId else {
                return .proceed
            }
            if let responseData {
                return .skipToWithData(stepId: targetStepId, data: responseData)
            }
            return .skipTo(stepId: targetStepId)

        default:
            return .proceed
        }
    }

    // MARK: - Variable interpolation (SPEC-083 §6.5, SPEC-088: delegates to shared TemplateEngine)

    private func interpolateVariables(_ value: String) -> String {
        let ctx = TemplateEngine.shared.buildContext()
        return TemplateEngine.shared.interpolate(value, context: ctx)
    }

    // MARK: - Hook result handling

    private func handleHookResult(_ result: StepAdvanceResult, step: OnboardingStep) {
        switch result {
        case .proceed:
            advanceOrComplete()

        case .proceedWithData(let extraData):
            mergeData(extraData, forStepId: step.id)
            // SPEC-088: Persist computed data for cross-module access
            SessionDataStore.shared.mergeComputedData(extraData)
            advanceOrComplete()

        case .block(let message):
            errorMessage = message
            withAnimation { showError = true }

        case .skipTo(let targetStepId):
            skipToStep(targetStepId)

        case .skipToWithData(let targetStepId, let extraData):
            mergeData(extraData, forStepId: step.id)
            // SPEC-088: Persist computed data for cross-module access
            SessionDataStore.shared.mergeComputedData(extraData)
            skipToStep(targetStepId)
        }
    }

    // MARK: - Hook event tracking

    private func trackHookEvent(_ event: String, step: OnboardingStep, extra: [String: Any] = [:]) {
        var props: [String: Any] = [
            "flow_id": flow.id,
            "step_id": step.id,
        ]
        props.merge(extra) { _, new in new }
        eventTracker?.track(event: event, properties: props)
    }

    private func resultName(_ result: StepAdvanceResult) -> String {
        switch result {
        case .proceed: return "proceed"
        case .proceedWithData: return "proceed_with_data"
        case .block: return "block"
        case .skipTo: return "skip_to"
        case .skipToWithData: return "skip_to"
        }
    }

    // MARK: - Navigation helpers

    private func handleStepSkipped(step: OnboardingStep) {
        onStepSkipped(step.id, currentIndex)
        advanceOrComplete()
    }

    private func advanceOrComplete() {
        let currentStep = flow.steps[currentIndex]

        // Check next_step_rules for branching / paywall triggers / end nodes
        if let rules = currentStep.next_step_rules,
           let firstRule = rules.first {
            let target = firstRule.target_step_id

            // Check for special graph nodes
            if target.hasPrefix("paywall_trigger_") {
                // Extract paywall ID from graph node data and present it
                if let paywallId = resolvePaywallFromTrigger(target) {
                    let flowCompleted = onFlowCompleted
                    let currentResponses = responses
                    let tracker = eventTracker
                    let flowId = flow.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard let vc = AppDNA.topViewController() else {
                            flowCompleted(currentResponses)
                            return
                        }
                        // Present paywall with delegate that resumes flow on dismiss
                        let bridge = OnboardingPaywallBridge(onDismissed: {
                                // Paywall dismissed (purchased or not) — complete the onboarding flow
                            tracker?.track(event: "onboarding_completed", properties: [
                                "flow_id": flowId,
                                "paywall_id": paywallId,
                                "completed_via": "paywall_trigger",
                            ])
                            flowCompleted(currentResponses)
                        })
                        AppDNA.presentPaywall(id: paywallId, from: vc, delegate: bridge)
                    }
                } else {
                    onFlowCompleted(responses)
                }
                return
            } else if target.hasPrefix("end_") {
                onFlowCompleted(responses)
                return
            } else if let targetIndex = flow.steps.firstIndex(where: { $0.id == target }) {
                // Navigate to specific step
                withAnimation { currentIndex = targetIndex }
                return
            }
        }

        // Default: sequential advance
        if currentIndex + 1 >= flow.steps.count {
            onFlowCompleted(responses)
        } else {
            withAnimation { currentIndex += 1 }
        }
    }

    /// Resolve paywall ID from a paywall_trigger graph node.
    /// The graph_layout stores the paywall ID in the node's data.
    private func resolvePaywallFromTrigger(_ triggerNodeId: String) -> String? {
        guard let graphLayout = flow.graph_layout?.value as? [String: Any],
              let nodes = graphLayout["nodes"] as? [[String: Any]] else { return nil }
        guard let node = nodes.first(where: { ($0["id"] as? String) == triggerNodeId }) else { return nil }
        guard let data = node["data"] as? [String: Any] else { return nil }
        return data["paywall_id"] as? String ?? data["paywallId"] as? String
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

// MARK: - SPEC-087: Template interpolation helper

/// Interpolates `{{variable}}` patterns in onboarding text fields via shared TemplateEngine.
extension String {
    func interpolated() -> String {
        guard self.contains("{{") else { return self }
        let ctx = TemplateEngine.shared.buildContext()
        return TemplateEngine.shared.interpolate(self, context: ctx)
    }
}

// MARK: - Step router

/// Routes to the appropriate step view based on step type.
struct OnboardingStepRouter: View {
    let step: OnboardingStep
    let effectiveConfig: StepConfig
    let onNext: ([String: Any]?) -> Void
    let onSkip: () -> Void
    /// Flow ID for chat webhook context
    var flowId: String = ""
    /// Current step index (0-based) for auto-binding page_indicator / progress_bar.
    var currentStepIndex: Int = 0
    /// Total steps in the flow for auto-binding page_indicator / progress_bar.
    var totalSteps: Int = 1

    @State private var toggleValues: [String: Bool] = [:]
    @State private var inputValues: [String: Any] = [:]

    // SPEC-084: Localization helper for step text
    // SPEC-087: Also interpolates {{variables}} after localization
    private func loc(_ key: String, _ fallback: String) -> String {
        let localized = LocalizationEngine.resolve(key: key, localizations: effectiveConfig.localizations, defaultLocale: effectiveConfig.default_locale, fallback: fallback)
        let ctx = TemplateEngine.shared.buildContext()
        return TemplateEngine.shared.interpolate(localized, context: ctx)
    }

    var body: some View {
        ZStack {
            // SPEC-084: Step-level background
            if let bg = effectiveConfig.background {
                StyleEngine.backgroundView(bg).ignoresSafeArea()
            }

            // SPEC-084: Block-based vs legacy rendering
            if let blocks = effectiveConfig.content_blocks, !blocks.isEmpty {
                blockBasedStepView(blocks: blocks)
            } else {
                legacyStepView
            }
        }
        .entryAnimation(effectiveConfig.animation?.entry_animation, durationMs: effectiveConfig.animation?.entry_duration_ms)
    }

    // MARK: - Block-based step view (SPEC-084)

    @ViewBuilder
    private func blockBasedStepView(blocks: [ContentBlock]) -> some View {
        let variant = effectiveConfig.layout_variant ?? "no_image"

        switch variant {
        case "image_fullscreen":
            ZStack {
                if let url = effectiveConfig.image_url {
                    AsyncImage(url: URL(string: url)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill).ignoresSafeArea()
                        }
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                        .ignoresSafeArea()
                }
                ScrollView {
                    VStack(spacing: 12) {
                        Spacer(minLength: 200)
                        ContentBlockRendererView(blocks: blocks, onAction: handleBlockAction, toggleValues: $toggleValues, loc: loc, inputValues: $inputValues, currentStepIndex: currentStepIndex, totalSteps: totalSteps)
                            .padding(.horizontal, 20)
                    }
                }
            }

        case "image_split":
            // 40/60 image-to-content split (SPEC-084 Gap #15)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if let url = effectiveConfig.image_url {
                        AsyncImage(url: URL(string: url)) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: geometry.size.width * 0.4)
                        .clipped()
                    }
                    ScrollView {
                        ContentBlockRendererView(blocks: blocks, onAction: handleBlockAction, toggleValues: $toggleValues, loc: loc, inputValues: $inputValues, currentStepIndex: currentStepIndex, totalSteps: totalSteps)
                            .padding(16)
                    }
                    .frame(width: geometry.size.width * 0.6)
                }
            }

        case "image_bottom":
            ScrollView {
                VStack(spacing: 12) {
                    ContentBlockRendererView(blocks: blocks, onAction: handleBlockAction, toggleValues: $toggleValues, loc: loc, inputValues: $inputValues, currentStepIndex: currentStepIndex, totalSteps: totalSteps)
                        .padding(.horizontal, 20)
                    if let url = effectiveConfig.image_url {
                        AsyncImage(url: URL(string: url)) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 240)
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
            }

        case "image_top":
            ScrollView {
                VStack(spacing: 12) {
                    if let url = effectiveConfig.image_url {
                        AsyncImage(url: URL(string: url)) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 240)
                            }
                        }
                    }
                    ContentBlockRendererView(blocks: blocks, onAction: handleBlockAction, toggleValues: $toggleValues, loc: loc, inputValues: $inputValues, currentStepIndex: currentStepIndex, totalSteps: totalSteps)
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)
            }

        default: // no_image
            ScrollView {
                ContentBlockRendererView(blocks: blocks, onAction: handleBlockAction, toggleValues: $toggleValues, loc: loc, inputValues: $inputValues, currentStepIndex: currentStepIndex, totalSteps: totalSteps)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Legacy step view (backward compat)

    @ViewBuilder
    private var legacyStepView: some View {
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
                FormStepView(config: effectiveConfig, onNext: onNext, apiClient: AppDNA.geocodeClient)
            case .interactive_chat:
                ChatStepView(step: step, flowId: flowId, onNext: { data in onNext(data) }, onSkip: onSkip)
            }

            if step.config.skip_enabled == true {
                Button("Skip") { onSkip() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Block action handler

    private func handleBlockAction(_ action: String, _ actionValue: String?) {
        switch action {
        case "next":
            // Collect toggle values and input values into response
            var data: [String: Any] = [:]
            for (key, value) in toggleValues {
                data["toggle_\(key)"] = value
            }
            // SPEC-089d Phase 3: Include form input values in step response
            for (key, value) in inputValues {
                data[key] = value
            }
            onNext(data.isEmpty ? nil : data)
        case "skip":
            onSkip()
        case "link":
            if let urlString = actionValue, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url)
                }
            }
            onNext(nil)
        case "social_login":
            // SPEC-089d AC-015: Social login fires onBeforeStepAdvance with provider info.
            // The app delegate handles auth and returns .proceedWithData or .block.
            let data: [String: Any] = [
                "provider": actionValue ?? "unknown",
                "action": "social_login",
            ]
            onNext(data)
        case "permission":
            // P1: Requires runtime permission request infrastructure.
            // action_value will specify the permission type (e.g. "camera", "notifications").
            // For now, advance the step as a safe fallback.
            onNext(nil)
        default:
            onNext(nil)
        }
    }
}

// MARK: - Paywall Bridge for Onboarding Flow Continuation

/// Bridges paywall dismiss back to onboarding flow completion.
/// Kept as a strong reference until paywall dismisses.
private class OnboardingPaywallBridge: AppDNAPaywallDelegate {
    private let onDismissed: () -> Void

    init(onDismissed: @escaping () -> Void) {
        self.onDismissed = onDismissed
    }

    func onPaywallDismissed(paywallId: String) {
        onDismissed()
    }

    func onPaywallPurchaseCompleted(paywallId: String, productId: String, transaction: TransactionInfo) {
        // Purchase succeeded — flow will complete via onDismissed
    }
}
