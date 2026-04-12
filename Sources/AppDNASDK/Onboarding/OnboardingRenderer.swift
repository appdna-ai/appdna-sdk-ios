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
    @State private var navigationHistory: [Int] = [] // Stack of visited step indices for back navigation
    @State private var responses: [String: Any] = [:]

    // SPEC-083: Hook state
    @State private var isProcessing = false
    @State private var loadingText: String = "Processing..."
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var configOverrides: [String: StepConfigOverride] = [:]

    /// True while the SDK is prefetching images for the NEXT step. During this
    /// time the current step remains visible (instead of showing an empty screen
    /// with unloaded image placeholders).
    @State private var isPreloadingNextStep = false

    /// True on the very first render until the first step's remote images are
    /// in the URL cache. Prevents the "one-frame flash with no background"
    /// effect when the onboarding is first presented.
    @State private var isInitialLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar (hidden per-step via hide_progress while still counting in total)
            if flow.settings.show_progress && !(currentIndex < flow.steps.count && flow.steps[currentIndex].hide_progress == true) {
                progressBar
            }

            // Navigation bar — only render when back button or dismiss button is visible
            if (flow.settings.allow_back && !navigationHistory.isEmpty) || (flow.settings.dismiss_allowed ?? true) {
                navigationBar
            }

            // Step content — fills remaining space
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
                        totalSteps: flow.steps.count,
                        savedResponses: responses[step.id] as? [String: Any]
                    )
                    // Chat steps use stable step.id so back-navigation preserves chat transcript;
                    // other steps use currentIndex to force view recreation for transition animations.
                    .id(step.type == .interactive_chat ? AnyHashable(step.id) : AnyHashable(currentIndex))
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
                .frame(maxHeight: .infinity)
                .onAppear {
                    handleStepAppear(step: step)
                }
                // Hide step content on the very first render until the initial
                // image prefetch completes, so users never see an unstyled
                // frame before the background image arrives.
                .opacity(isInitialLoading ? 0 : 1)
            }
        }
        // Step background renders full-screen behind progress bar + nav bar + content
        .background(
            stepFullScreenBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .task {
            guard isInitialLoading else { return }
            if currentIndex < flow.steps.count {
                let urls = collectImageURLs(from: flow.steps[currentIndex])
                if !urls.isEmpty {
                    await ImagePreloader.prefetch(urls: urls, timeout: 3.0)
                }
            }
            isInitialLoading = false
        }
    }

    // MARK: - Full-screen step background

    @ViewBuilder
    private var stepFullScreenBackground: some View {
        if currentIndex < flow.steps.count {
            let step = flow.steps[currentIndex]
            let cfg = applyOverrides(to: step.config, stepId: step.id)
            if let bg = cfg.background {
                // Step-level background (image, gradient, color)
                StyleEngine.backgroundView(bg)
            } else if let chatBg = cfg.chat_config?.style?.background_color {
                // Chat steps store background in chat style config
                Color(hex: chatBg)
            } else if step.type == .interactive_chat {
                // Chat step fallback default (dark)
                Color(hex: "#0F172A")
            } else {
                Color(.systemBackground)
            }
        } else {
            Color(.systemBackground)
        }
    }

    // MARK: - Progress bar

    @ViewBuilder
    private var progressBar: some View {
        let trackColor: Color = {
            if let hex = flow.settings.progress_track_color { return Color(hex: hex) }
            return Color.gray.opacity(0.2)
        }()
        // Per-step progress color override: step.config.progress_color > element_style.background.color > flow.settings.progress_color
        let fillColor: Color = {
            if currentIndex < flow.steps.count {
                let step = flow.steps[currentIndex]
                if let stepColor = step.config.progress_color, !stepColor.isEmpty {
                    return Color(hex: stepColor)
                }
                if let stepColor = step.config.element_style?.background?.color {
                    return Color(hex: stepColor)
                }
            }
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
            let _ = Log.debug("[Onboarding] Nav bar: allow_back=\(flow.settings.allow_back), currentIndex=\(currentIndex), isProcessing=\(isProcessing)")
            if flow.settings.allow_back && !navigationHistory.isEmpty {
                Button {
                    let previousIndex = navigationHistory.last ?? max(currentIndex - 1, 0)
                    Log.debug("[Onboarding] Back button tapped, going from \(currentIndex) to \(previousIndex)")
                    navigationHistory.removeLast()
                    withAnimation(.easeInOut(duration: 0.25)) { currentIndex = previousIndex }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: backSize, weight: .semibold))
                        .foregroundColor(backColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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

        let isSocialLogin = (data?["action"] as? String) == "social_login"

        // SPEC-083: Determine hook type — client delegate takes priority over server hook
        if delegate != nil {
            // Client-side hook — for social_login, the delegate handles auth and returns
            // .proceed/.proceedWithData to advance, or .block to stay, or dismisses the host.
            executeClientHook(step: step, data: data)
        } else if let hook = step.hook, hook.enabled == true {
            // Server-side hook (P1)
            executeServerHook(step: step, data: data, hookConfig: hook)
        } else if isSocialLogin {
            // Social login without a delegate: do NOT auto-advance.
            // The app must implement AppDNAOnboardingDelegate to handle social auth.
            Log.warning("[Onboarding] social_login action received but no delegate is set. Implement AppDNAOnboardingDelegate to handle social auth.")
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
        let effectiveConfig = applyOverrides(to: currentStep.config, stepId: currentStep.id)

        // Prefer layout.next_step_rules (has Logic panel conditions) over step-level rules
        let stepRules = currentStep.next_step_rules ?? []
        let layoutRules = effectiveConfig.next_step_rules ?? []
        let hasLayoutConditions = layoutRules.contains { $0.conditions != nil && !($0.conditions?.isEmpty ?? true) }
        let hasStepConditions = stepRules.contains { $0.conditions != nil && !($0.conditions?.isEmpty ?? true) }
        let rules: [NextStepRule] = hasLayoutConditions && !hasStepConditions ? layoutRules : stepRules

        let stepResponses = responses[currentStep.id] as? [String: Any] ?? [:]
        Log.debug("[Onboarding] advanceOrComplete step=\(currentStep.id), responses=\(stepResponses), usingLayoutRules=\(hasLayoutConditions && !hasStepConditions)")
        if !rules.isEmpty {
            Log.debug("[Onboarding] Evaluating \(rules.count) rules")
            for (ruleIdx, rule) in rules.enumerated() {
                let ruleMatch = evaluateRule(rule, stepId: currentStep.id)
                Log.debug("[Onboarding] Rule \(ruleIdx): target=\(rule.target_step_id), match=\(ruleMatch), conditions=\(String(describing: rule.conditions?.map { $0.value }))")
                // Evaluate condition(s) before following this rule
                if !ruleMatch {
                    continue // Condition not met, try next rule
                }
                let target = rule.target_step_id

                // Analytics event node — fire event, then follow downstream edge
                if target.hasPrefix("analytics_event_") {
                    // Get event details from graph_nodes
                    let nodeData = resolveGraphNode(target)
                    let eventName = nodeData?["event_name"] as? String ?? "onboarding_analytics"
                    eventTracker?.track(event: eventName, properties: [
                        "flow_id": flow.id, "node_id": target, "step_id": currentStep.id,
                    ])
                    // Follow downstream edge if available
                    if let nextTarget = nodeData?["next_target"] as? String,
                       let targetIndex = flow.steps.firstIndex(where: { $0.id == nextTarget }) {
                        navigate(to: targetIndex)
                        return
                    }
                    // No downstream target — continue to next rule
                    continue
                }

                // Paywall trigger node
                if target.hasPrefix("paywall_trigger_") {
                    if let paywallId = resolvePaywallFromTrigger(target) {
                        let triggerData = resolvePaywallTriggerData(target)
                        let onDismissBehavior = triggerData?["on_dismiss"] as? String ?? "continue"
                        let flowCompleted = onFlowCompleted
                        let currentResponses = responses
                        let tracker = eventTracker
                        let flowId = flow.id

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            guard let onboardingVC = AppDNA.topViewController() else {
                                flowCompleted(currentResponses)
                                return
                            }
                            onboardingVC.dismiss(animated: true) {
                                guard let rootVC = AppDNA.topViewController() else {
                                    flowCompleted(currentResponses)
                                    return
                                }

                                // Present paywall once. On dismiss (regardless of
                                // on_dismiss config), complete the flow. Never re-present.
                                let bridge = OnboardingPaywallBridge(
                                    onPurchased: {
                                        tracker?.track(event: "onboarding_completed", properties: [
                                            "flow_id": flowId, "paywall_id": paywallId, "completed_via": "paywall_purchased",
                                        ])
                                        flowCompleted(currentResponses)
                                    },
                                    onDismissedWithoutPurchase: {
                                        // Always complete flow on dismiss — no re-presentation.
                                        // The user pressed X, respect that decision.
                                        tracker?.track(event: "onboarding_completed", properties: [
                                            "flow_id": flowId, "paywall_id": paywallId, "completed_via": "paywall_dismissed",
                                        ])
                                        flowCompleted(currentResponses)
                                    }
                                )
                                AppDNA.presentPaywall(id: paywallId, from: rootVC, delegate: bridge)
                            }
                        }
                    } else {
                        onFlowCompleted(responses)
                    }
                    return
                }

                // End node
                if target.hasPrefix("end_") {
                    onFlowCompleted(responses)
                    return
                }

                // Navigate to a specific step
                if let targetIndex = flow.steps.firstIndex(where: { $0.id == target }) {
                    navigate(to: targetIndex)
                    return
                }
            }
        }

        // Default: sequential advance
        if currentIndex + 1 >= flow.steps.count {
            onFlowCompleted(responses)
        } else {
            navigate(to: currentIndex + 1)
        }
    }

    // MARK: - Navigation with image preload

    /// Advance to the given step index, prefetching any remote images referenced
    /// in the target step's content blocks BEFORE updating currentIndex. This
    /// prevents the new screen from flashing with empty image placeholders while
    /// the network downloads the assets.
    private func navigate(to targetIndex: Int, appendHistory: Bool = true) {
        guard targetIndex >= 0 && targetIndex < flow.steps.count else { return }
        let targetStep = flow.steps[targetIndex]
        let urls = collectImageURLs(from: targetStep)

        let performNavigation: () -> Void = {
            if appendHistory { navigationHistory.append(currentIndex) }
            withAnimation { currentIndex = targetIndex }
        }

        if urls.isEmpty {
            performNavigation()
            return
        }

        isPreloadingNextStep = true
        ImagePreloader.prefetch(urls: urls, timeout: 3.0) {
            isPreloadingNextStep = false
            performNavigation()
        }
    }

    /// Walk a step's content to collect every remote image URL that will be
    /// rendered when the step displays. Static so the flow manager can call
    /// it to kick off prefetching before the host view is even created.
    static func collectImageURLs(from step: OnboardingStep) -> [URL] {
        var urls: [URL] = []

        // Step-level image (welcome/value_prop/custom layouts)
        if let s = step.config.image_url, let u = URL(string: s) {
            urls.append(u)
        }

        // Step background image
        if let bg = step.config.background?.image_url, let u = URL(string: bg) {
            urls.append(u)
        }

        // Recurse content blocks
        if let blocks = step.config.content_blocks {
            for block in blocks {
                urls.append(contentsOf: collectImageURLs(from: block))
            }
        }

        return urls
    }

    private func collectImageURLs(from step: OnboardingStep) -> [URL] {
        Self.collectImageURLs(from: step)
    }

    /// Recursive helper to walk nested content blocks (stack/row containers) and
    /// collect their image URLs.
    static func collectImageURLs(from block: ContentBlock) -> [URL] {
        var urls: [URL] = []
        if let s = block.image_url, let u = URL(string: s) {
            urls.append(u)
        }
        if let s = block.placeholder_image_url, let u = URL(string: s) {
            urls.append(u)
        }
        if let options = block.field_options {
            for opt in options {
                if let s = opt.image_url, let u = URL(string: s) {
                    urls.append(u)
                }
            }
        }
        // Container children (stack / row / card)
        let kids = (block.children ?? []) + (block.stack_children ?? [])
        for child in kids {
            urls.append(contentsOf: collectImageURLs(from: child))
        }
        return urls
    }

    // MARK: - Condition Evaluation

    /// Evaluate whether a navigation rule's conditions are met based on current responses.
    private func evaluateRule(_ rule: NextStepRule, stepId: String) -> Bool {
        // Prefer `conditions` array, fall back to single `condition`
        let conditionList: [Any]
        if let conditions = rule.conditions {
            conditionList = conditions.map { $0.value }
        } else if let condition = rule.condition {
            conditionList = [condition.value]
        } else {
            return true // No condition = always match
        }

        let logic = rule.logic ?? "and"
        let stepResponses = responses[stepId] as? [String: Any] ?? [:]

        for cond in conditionList {
            let matches: Bool
            if let condStr = cond as? String {
                matches = condStr == "always"
            } else if let condDict = cond as? [String: Any] {
                matches = evaluateCondition(condDict, responses: stepResponses)
            } else {
                matches = true
            }

            if logic == "or" && matches { return true }
            if logic == "and" && !matches { return false }
        }

        return logic == "and" // All passed for "and", none passed for "or"
    }

    /// The step ID the user navigated FROM to reach the current step, or nil
    /// if there is no previous step (i.e. this is the first step).
    private var previousStepId: String? {
        guard let lastIdx = navigationHistory.last,
              lastIdx >= 0, lastIdx < flow.steps.count else { return nil }
        return flow.steps[lastIdx].id
    }

    /// Evaluate a single condition dict against step responses.
    private func evaluateCondition(_ cond: [String: Any], responses: [String: Any]) -> Bool {
        guard let type = cond["type"] as? String else { return true }
        // Console saves "answer_key", SDK also checks "field" for backward compat
        let field = cond["answer_key"] as? String ?? cond["field"] as? String ?? ""

        switch type {
        case "always":
            return true
        case "answer_equals":
            let expected = cond["value"]
            let actual = responses[field]
            // Handle array values (multiselect stores ["opt_2"] not "opt_2")
            if let actualArray = actual as? [String], let expectedStr = expected as? String {
                return actualArray.contains(expectedStr)
            }
            return isEqual(actual, expected)
        case "answer_contains":
            let expected = cond["value"] as? String ?? ""
            let actual = responses[field] as? String ?? ""
            return actual.contains(expected)
        case "answer_not_equals":
            let expected = cond["value"]
            let actual = responses[field]
            if let actualArray = actual as? [String], let expectedStr = expected as? String {
                return !actualArray.contains(expectedStr)
            }
            return !isEqual(actual, expected)
        case "not_empty":
            let actual = responses[field]
            if let str = actual as? String { return !str.isEmpty }
            return actual != nil
        case "empty":
            let actual = responses[field]
            if let str = actual as? String { return str.isEmpty }
            return actual == nil
        case "previous_step_equals":
            // Match if the step the user came FROM equals the given step ID.
            // Used for conditional paywall routing: "if came from 12a → paywall_a".
            guard let prevId = previousStepId else { return false }
            let expected = cond["value"] as? String ?? ""
            return prevId == expected
        case "previous_step_in":
            // Match if the previous step ID is one of the listed IDs.
            guard let prevId = previousStepId else { return false }
            // Console saves as "previous_step_ids" array. AnyCodable decodes JSON arrays
            // as [Any] under the hood, so we accept both [String] and [Any] casts.
            if let ids = cond["previous_step_ids"] as? [String] {
                return ids.contains(prevId)
            }
            if let anyArray = cond["previous_step_ids"] as? [Any] {
                let ids = anyArray.compactMap { $0 as? String }
                return ids.contains(prevId)
            }
            // Fallback: comma-separated string in "value" (legacy/manual edit)
            if let csv = cond["value"] as? String {
                let ids = csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return ids.contains(prevId)
            }
            return false
        default:
            return true // Unknown condition type = pass
        }
    }

    private func isEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        if let aStr = a as? String, let bStr = b as? String { return aStr == bStr }
        if let aNum = a as? Double, let bNum = b as? Double { return aNum == bNum }
        if let aInt = a as? Int, let bInt = b as? Int { return aInt == bInt }
        if let aBool = a as? Bool, let bBool = b as? Bool { return aBool == bBool }
        return String(describing: a) == String(describing: b)
    }

    /// Resolve any graph node data by ID from graph_nodes.
    private func resolveGraphNode(_ nodeId: String) -> [String: Any]? {
        if let graphNodes = flow.graph_nodes?.value as? [String: Any],
           let node = graphNodes[nodeId] as? [String: Any] {
            return node
        }
        return nil
    }

    /// Resolve paywall ID from a paywall_trigger graph node.
    private func resolvePaywallFromTrigger(_ triggerNodeId: String) -> String? {
        return resolvePaywallTriggerData(triggerNodeId)?["paywall_id"] as? String
            ?? resolvePaywallTriggerData(triggerNodeId)?["paywallId"] as? String
    }

    /// Returns the data dict for a paywall_trigger node.
    /// Checks graph_nodes first (lightweight, always synced), then falls back to graph_layout.
    private func resolvePaywallTriggerData(_ triggerNodeId: String) -> [String: Any]? {
        // Prefer graph_nodes (lightweight dict keyed by node ID)
        if let graphNodes = flow.graph_nodes?.value as? [String: Any],
           let node = graphNodes[triggerNodeId] as? [String: Any] {
            return node
        }
        // Fallback to full graph_layout for backward compatibility
        if let graphLayout = flow.graph_layout?.value as? [String: Any],
           let nodes = graphLayout["nodes"] as? [[String: Any]],
           let node = nodes.first(where: { ($0["id"] as? String) == triggerNodeId }) {
            return node["data"] as? [String: Any]
        }
        return nil
    }

    private func skipToStep(_ targetStepId: String) {
        guard let targetIndex = flow.steps.firstIndex(where: { $0.id == targetStepId }) else {
            advanceOrComplete()
            return
        }
        // Route through navigate(to:) so images for the target step are
        // prefetched before the transition animates.
        navigate(to: targetIndex)
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
    /// Previously saved responses for this step (for input retention on back navigation).
    var savedResponses: [String: Any]? = nil

    @State private var toggleValues: [String: Bool] = [:]
    @State private var inputValues: [String: Any]
    @State private var showValidationToast = false

    init(step: OnboardingStep, effectiveConfig: StepConfig, onNext: @escaping ([String: Any]?) -> Void, onSkip: @escaping () -> Void, flowId: String = "", currentStepIndex: Int = 0, totalSteps: Int = 1, savedResponses: [String: Any]? = nil) {
        self.step = step
        self.effectiveConfig = effectiveConfig
        self.onNext = onNext
        self.onSkip = onSkip
        self.flowId = flowId
        self.currentStepIndex = currentStepIndex
        self.totalSteps = totalSteps
        self.savedResponses = savedResponses
        // Pre-populate inputValues from saved responses so child views see data immediately
        _inputValues = State(initialValue: savedResponses ?? [:])
    }

    // SPEC-084: Localization helper for step text
    // SPEC-087: Also interpolates {{variables}} after localization
    private func loc(_ key: String, _ fallback: String) -> String {
        let localized = LocalizationEngine.resolve(key: key, localizations: effectiveConfig.localizations, defaultLocale: effectiveConfig.default_locale, fallback: fallback)
        let ctx = TemplateEngine.shared.buildContext()
        return TemplateEngine.shared.interpolate(localized, context: ctx)
    }

    var body: some View {
        Group {
            if let blocks = effectiveConfig.content_blocks, !blocks.isEmpty {
                blockBasedStepView(blocks: blocks)
            } else {
                legacyStepView
            }
        }
        // Background is rendered at the OnboardingFlowHost level (full-screen behind nav bar)
        // Keyboard dismiss handled by ScrollView .scrollDismissesKeyboard in ThreeZoneStepLayout
        // Intercept links to open in-app instead of Safari
        .environment(\.openURL, OpenURLAction { url in
            InAppBrowser.present(url: url)
            return .handled
        })
        // inputValues pre-populated from savedResponses in init()
        // Validation toast overlay
        .overlay(alignment: .bottom) {
            if showValidationToast {
                let blocks = effectiveConfig.content_blocks ?? []
                let missingBlock = blocks.first(where: { b in
                    guard b.field_required == true else { return false }
                    let fieldId = b.field_id ?? b.id
                    let v = inputValues[fieldId]
                    return v == nil || (v as? String)?.isEmpty == true
                })
                Text("Please fill in \(missingBlock?.field_label ?? "required fields")")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            // image_fullscreen: background image is rendered in parent ZStack via step.background.
            // The layout_variant image_url is a legacy field — skip it here to avoid double-rendering.
            // Just use the three-zone layout which fills the parent ZStack.
            threeZoneLayout(blocks: blocks)

        case "image_split":
            // 40/60 image-to-content split (SPEC-084 Gap #15)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if let url = effectiveConfig.image_url {
                        BundledAsyncPhaseImage(url: URL(string: url)) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: geometry.size.width * 0.4)
                        .clipped()
                    }
                    threeZoneLayout(blocks: blocks)
                        .frame(width: geometry.size.width * 0.6)
                }
            }

        case "image_bottom", "image_top":
            // image_top/image_bottom: background images rendered by parent ZStack.
            // layout_variant image_url is legacy — background.image_url is the source of truth.
            threeZoneLayout(blocks: blocks)

        default: // no_image
            threeZoneLayout(blocks: blocks)
        }
    }

    // MARK: - Three-zone layout helper

    @ViewBuilder
    private func threeZoneLayout(blocks: [ContentBlock]) -> some View {
        ThreeZoneStepLayout(
            blocks: blocks,
            onAction: handleBlockAction,
            toggleValues: $toggleValues,
            loc: loc,
            inputValues: $inputValues,
            currentStepIndex: currentStepIndex,
            totalSteps: totalSteps
        )
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
                FormStepView(config: effectiveConfig, onNext: onNext, apiClient: AppDNA.geocodeClient, savedValues: savedResponses)
            case .interactive_chat:
                ChatStepView(step: step, flowId: flowId, onNext: { data in onNext(data) }, onSkip: onSkip, savedTranscript: savedResponses)
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

    /// Check if all required input blocks have values
    private var canAdvance: Bool {
        guard let blocks = effectiveConfig.content_blocks else { return true }
        for block in blocks where block.field_required == true {
            let fieldId = block.field_id ?? block.id
            let value = inputValues[fieldId]
            if value == nil { return false }
            if let str = value as? String, str.isEmpty { return false }
            if let dict = value as? [String: Any], dict.isEmpty { return false }
        }
        return true
    }

    private func handleBlockAction(_ action: String, _ actionValue: String?) {
        switch action {
        case "next":
            // Validate required fields before advancing
            guard canAdvance else {
                withAnimation { showValidationToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showValidationToast = false }
                }
                return
            }
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
                    InAppBrowser.present(url: url)
                }
            }
            // Don't advance — user will return from in-app browser
        case "social_login":
            // Social login: pass provider info via onNext but mark as social_login.
            // The flow host's handleStepCompleted will fire onBeforeStepAdvance hook.
            // The delegate handles auth and returns:
            //   - .proceedWithData to advance with auth data
            //   - .block("Signing in...") to stay on step while auth happens
            //   - .proceed to advance immediately
            // The data includes "action": "social_login" so the flow host knows not to
            // auto-advance if no delegate is set.
            var data: [String: Any] = [
                "provider": actionValue ?? "unknown",
                "action": "social_login",
            ]
            // Include any form input values collected on this step
            for (key, value) in inputValues {
                data[key] = value
            }
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

/// Bridges paywall events back to onboarding flow.
/// Handles both purchase and dismiss-without-purchase separately.
private class OnboardingPaywallBridge: AppDNAPaywallDelegate {
    private let onPurchased: () -> Void
    private let onDismissedWithoutPurchase: () -> Void
    private var didPurchase = false

    init(onPurchased: @escaping () -> Void, onDismissedWithoutPurchase: @escaping () -> Void) {
        self.onPurchased = onPurchased
        self.onDismissedWithoutPurchase = onDismissedWithoutPurchase
    }

    func onPaywallPurchaseCompleted(paywallId: String, productId: String, transaction: TransactionInfo) {
        didPurchase = true
    }

    func onPaywallDismissed(paywallId: String) {
        if didPurchase {
            onPurchased()
        } else {
            onDismissedWithoutPurchase()
        }
    }
}
