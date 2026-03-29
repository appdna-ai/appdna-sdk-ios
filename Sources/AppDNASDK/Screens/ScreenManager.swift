import Foundation
import UIKit

/// Central manager for server-driven screens. Handles config loading, caching,
/// trigger evaluation, slot resolution, navigation interception, and screen presentation.
internal class ScreenManager {
    static let shared = ScreenManager()

    private var screenIndex: ScreenIndex?
    private var screenCache: [String: ScreenConfig] = [:]
    private var flowCache: [String: FlowConfig] = [:]
    private var nestingDepth: Int = 0
    private let maxNestingDepth = 5
    private let lock = NSLock()

    // MARK: - Config Loading

    func updateIndex(_ index: ScreenIndex) {
        lock.lock()
        self.screenIndex = index
        lock.unlock()
    }

    func getCachedScreen(_ screenId: String) -> ScreenConfig? {
        lock.lock()
        defer { lock.unlock() }
        return screenCache[screenId]
    }

    func cacheScreen(_ screenId: String, config: ScreenConfig) {
        lock.lock()
        screenCache[screenId] = config
        lock.unlock()
    }

    func getCachedFlow(_ flowId: String) -> FlowConfig? {
        lock.lock()
        defer { lock.unlock() }
        return flowCache[flowId]
    }

    func cacheFlow(_ flowId: String, config: FlowConfig) {
        lock.lock()
        flowCache[flowId] = config
        lock.unlock()
    }

    // MARK: - Show Screen (Manual API)

    func showScreen(_ screenId: String, completion: ((ScreenResult) -> Void)? = nil) {
        // Thread-safe nesting depth check (AC-090)
        lock.lock()
        guard nestingDepth < maxNestingDepth else {
            lock.unlock()
            print("[SDUI] Max nesting depth (\(maxNestingDepth)) exceeded for screen: \(screenId)")
            completion?(ScreenResult(screenId: screenId, dismissed: true, error: .nestingDepthExceeded))
            return
        }
        nestingDepth += 1
        lock.unlock()
        let startTime = Date()

        // Try cache first
        if let cached = getCachedScreen(screenId) {
            presentScreen(cached, screenId: screenId, startTime: startTime, completion: completion)
            return
        }

        // Fetch from Firestore on-demand
        // In production, this would call RemoteConfigManager.fetchScreenConfig()
        // For now, fire callback with error if not cached
        completion?(ScreenResult(screenId: screenId, dismissed: true, error: .screenNotFound))
        nestingDepth -= 1
    }

    func showFlow(_ flowId: String, completion: ((FlowResult) -> Void)? = nil) {
        if let cached = getCachedFlow(flowId) {
            presentFlow(cached, flowId: flowId, completion: completion)
            return
        }

        completion?(FlowResult(flowId: flowId, error: .screenNotFound))
    }

    func dismissScreen() {
        DispatchQueue.main.async {
            if let topVC = UIApplication.shared.topViewController {
                topVC.dismiss(animated: true)
            }
        }
    }

    // MARK: - Preview (Debug)

    #if DEBUG
    func previewScreen(json: String, completion: ((ScreenResult) -> Void)? = nil) {
        guard let data = json.data(using: .utf8) else {
            print("[SDUI] Invalid JSON string for preview")
            completion?(ScreenResult(screenId: "preview", dismissed: true, error: .configParseError))
            return
        }

        do {
            let config = try JSONDecoder().decode(ScreenConfig.self, from: data)
            let startTime = Date()
            presentScreen(config, screenId: config.id ?? "preview", startTime: startTime, completion: completion)
        } catch {
            print("[SDUI] Failed to parse preview JSON: \(error)")
            completion?(ScreenResult(screenId: "preview", dismissed: true, error: .configParseError))
        }
    }
    #endif

    // MARK: - Presentation

    private func presentScreen(_ config: ScreenConfig, screenId: String, startTime: Date, completion: ((ScreenResult) -> Void)?) {
        // Validate config (AC-088, AC-089)
        let sections = config.sections ?? []
        guard !sections.isEmpty else {
            completion?(ScreenResult(screenId: screenId, dismissed: true, error: .configInvalid))
            nestingDepth -= 1
            return
        }

        // Check scheduling (AC-098, AC-099)
        if let startDate = config.start_date, let date = ISO8601DateFormatter().date(from: startDate), date > Date() {
            completion?(ScreenResult(screenId: screenId, dismissed: true))
            nestingDepth -= 1
            return
        }
        if let endDate = config.end_date, let date = ISO8601DateFormatter().date(from: endDate), date < Date() {
            completion?(ScreenResult(screenId: screenId, dismissed: true))
            nestingDepth -= 1
            return
        }

        // Resolve experiment variants (AC-093, AC-094)
        var resolvedConfig = config
        var variantKey: String?
        if let experimentId = config.experiment_id, let variants = config.variants {
            // Check experiment bucketing
            if let bucket = AppDNA.getExperimentVariant(experimentId: experimentId) {
                variantKey = bucket
                if let override = variants[bucket] {
                    // Apply variant overrides
                    if let overrideSections = override.sections { resolvedConfig = ScreenConfig(
                        id: config.id, name: config.name, version: config.version,
                        presentation: override.presentation ?? config.presentation,
                        transition: config.transition, layout: config.layout,
                        sections: overrideSections,
                        background: override.background ?? config.background,
                        dismiss: config.dismiss, nav_bar: config.nav_bar,
                        haptic: config.haptic, particle_effect: config.particle_effect,
                        localizations: config.localizations, default_locale: config.default_locale,
                        audience_rules: config.audience_rules, trigger_rules: config.trigger_rules,
                        slot_config: config.slot_config, start_date: config.start_date,
                        end_date: config.end_date, min_sdk_version: config.min_sdk_version,
                        experiment_id: config.experiment_id, variants: config.variants,
                        analytics_name: config.analytics_name
                    )}
                }
            }
        }

        // Build context
        let context = SectionContext(
            screenId: screenId,
            onAction: { [weak self] action in
                self?.handleAction(action, screenId: screenId, startTime: startTime, completion: completion)
            }
        )

        // Track event (AC-095: include experiment_id and variant_key)
        var trackProps: [String: Any] = [
            "screen_id": screenId,
            "screen_name": resolvedConfig.name,
            "presentation": resolvedConfig.presentation,
        ]
        if let expId = config.experiment_id { trackProps["experiment_id"] = expId }
        if let vk = variantKey { trackProps["variant_key"] = vk }
        AppDNA.track(event:"screen_presented", properties: trackProps)

        // Present via PresentationCoordinator
        PresentationCoordinator.shared.requestPresentation(type: .screen) {
            ScreenPresenter.present(config: resolvedConfig, context: context) { [weak self] in
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                AppDNA.track(event:"screen_dismissed", properties: [
                    "screen_id": screenId,
                    "screen_name": config.name,
                    "duration_ms": duration,
                ])
                self?.nestingDepth -= 1
                completion?(ScreenResult(screenId: screenId, dismissed: true, duration_ms: duration))
            }
        }
    }

    private func presentFlow(_ config: FlowConfig, flowId: String, completion: ((FlowResult) -> Void)?) {
        // Collect screen configs for all screens in the flow
        var screens: [String: ScreenConfig] = [:]
        for ref in config.screens {
            if let screenConfig = getCachedScreen(ref.screen_id) {
                screens[ref.screen_id] = screenConfig
            }
        }

        let flowManager = FlowManager(flowConfig: config, screens: screens)
        flowManager.onComplete = { result in
            let eventName = result.completed ? "flow_completed" : "flow_abandoned"
            AppDNA.track(event:eventName, properties: [
                "flow_id": flowId,
                "flow_name": config.name,
                "screens_viewed": result.screensViewed,
                "duration_ms": result.duration_ms,
            ])
            completion?(result)
        }

        AppDNA.track(event:"flow_started", properties: [
            "flow_id": flowId,
            "flow_name": config.name,
            "start_screen_id": config.start_screen_id,
        ])

        ScreenPresenter.presentFlow(flowManager: flowManager)
    }

    // MARK: - Action Handling

    private func handleAction(_ action: SectionAction, screenId: String, startTime: Date, completion: ((ScreenResult) -> Void)?) {
        switch action {
        case .next:
            // For single screens (not flows), "next" dismisses the screen
            dismissScreen()

        case .back:
            // For single screens, "back" dismisses the screen
            dismissScreen()

        case .dismiss:
            dismissScreen()

        case .navigate(let targetScreenId):
            // Dismiss current and show target screen
            dismissScreen()
            showScreen(targetScreenId)

        case .openURL(let url):
            if let url = URL(string: url) {
                DispatchQueue.main.async { UIApplication.shared.open(url) }
            }

        case .openWebview(let url):
            if let url = URL(string: url) {
                DispatchQueue.main.async {
                    // SFSafariViewController would be used here
                    UIApplication.shared.open(url)
                }
            }

        case .openAppSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                DispatchQueue.main.async { UIApplication.shared.open(url) }
            }

        case .share(let text):
            DispatchQueue.main.async {
                let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                UIApplication.shared.topViewController?.present(vc, animated: true)
            }

        case .deepLink(let url):
            if let url = URL(string: url) {
                DispatchQueue.main.async { UIApplication.shared.open(url) }
            }

        case .showPaywall(let id):
            if let paywallId = id {
                AppDNA.showPaywall(paywallId)
            }

        case .showSurvey(let id):
            if let surveyId = id {
                AppDNA.showSurvey(surveyId)
            }

        case .showScreen(let id):
            showScreen(id)

        case .submitForm(let data):
            // Submit form data to backend
            AppDNA.track(event:"screen_response_submitted", properties: [
                "screen_id": screenId,
                "field_count": data.count,
            ])

        case .track(let event, let properties):
            AppDNA.track(event:event, properties: properties)

        case .haptic(let type):
            if let hapticType = HapticType(rawValue: type) {
                HapticEngine.trigger(hapticType)
            }

        case .custom(let type, let value):
            AppDNA.screenDelegate?.onScreenAction(screenId: screenId, action: action)

        default:
            break
        }

        // Track action
        AppDNA.track(event:"screen_action", properties: [
            "screen_id": screenId,
            "action_type": String(describing: action),
        ])
    }

    // MARK: - Slot Resolution (Mechanism 2)

    func screenForSlot(_ slotName: String) -> (screenId: String, config: ScreenConfig)? {
        guard let index = screenIndex, let slots = index.slots else { return nil }

        guard let assignment = slots.first(where: { $0.slot_name == slotName }) else { return nil }

        // Check audience rules
        let userTraits = AppDNA.getUserTraits()
        if let audienceRules = assignment.audience_rules {
            if !AudienceRuleEvaluator.evaluate(rules: audienceRules, userTraits: userTraits) {
                return nil
            }
        }

        // Get screen config
        guard let config = getCachedScreen(assignment.screen_id) else { return nil }

        return (assignment.screen_id, config)
    }

    // MARK: - Trigger Evaluation (Mechanism 1)

    func evaluateTriggers(event: String, properties: [String: Any]?) {
        guard let index = screenIndex, let screens = index.screens else { return }
        guard AppDNA.isConsentGranted() else { return }

        let userTraits = AppDNA.getUserTraits()

        // Find matching screens sorted by priority (highest first)
        let matchingScreens = screens
            .filter { entry in
                evaluateScreenTrigger(entry, event: event, properties: properties, userTraits: userTraits)
            }
            .sorted { ($0.priority ?? 0) > ($1.priority ?? 0) }

        // Show highest priority match
        if let match = matchingScreens.first {
            guard PresentationCoordinator.shared.canPresent(type: .screen, isAutoTriggered: true) else { return }
            showScreen(match.id)
        }
    }

    private func evaluateScreenTrigger(
        _ entry: ScreenIndexEntry,
        event: String,
        properties: [String: Any]?,
        userTraits: [String: Any]
    ) -> Bool {
        guard let triggerRules = entry.trigger_rules else { return false }

        // Check scheduling
        if let startDate = entry.start_date, let date = ISO8601DateFormatter().date(from: startDate), date > Date() {
            return false
        }
        if let endDate = entry.end_date, let date = ISO8601DateFormatter().date(from: endDate), date < Date() {
            return false
        }

        // Check audience rules
        if let audienceRules = entry.audience_rules {
            if !AudienceRuleEvaluator.evaluate(rules: audienceRules, userTraits: userTraits) {
                return false
            }
        }

        // Check event triggers
        if let events = triggerRules.events {
            let eventMatch = events.contains { trigger in
                guard trigger.event_name == event else { return false }
                // Check event property conditions
                if let conditions = trigger.conditions, let props = properties {
                    return conditions.allSatisfy { cond in
                        let propValue = props[cond.field]
                        return ConditionEvaluator.valuesEqual(propValue, cond.value?.value)
                    }
                }
                return true
            }
            if eventMatch { return true }
        }

        return false
    }

    // MARK: - Navigation Interception (Mechanism 3)

    private var interceptionEnabled = false
    private var interceptionScreenFilter: [String]?

    func enableNavigationInterception(forScreens: [String]? = nil) {
        interceptionEnabled = true
        interceptionScreenFilter = forScreens
    }

    func disableNavigationInterception() {
        interceptionEnabled = false
        interceptionScreenFilter = nil
    }

    func evaluateInterceptions(screenName: String, timing: String) {
        guard interceptionEnabled else { return }
        guard AppDNA.isConsentGranted() else { return }

        // Check filter
        if let filter = interceptionScreenFilter, !filter.contains(where: { matchGlob(pattern: $0, string: screenName) }) {
            return
        }

        guard let index = screenIndex, let interceptions = index.interceptions else { return }

        let userTraits = AppDNA.getUserTraits()

        for interception in interceptions {
            guard interception.timing == timing else { continue }
            guard matchGlob(pattern: interception.trigger_screen, string: screenName) else { continue }

            // Check audience rules
            if let audienceRules = interception.audience_rules {
                if !AudienceRuleEvaluator.evaluate(rules: audienceRules, userTraits: userTraits) {
                    continue
                }
            }

            // Track and show
            AppDNA.track(event:"interception_triggered", properties: [
                "trigger_screen": screenName,
                "timing": timing,
                "screen_id": interception.screen_id,
            ])

            showScreen(interception.screen_id)
            return // Only show one interception per navigation
        }
    }

    /// Glob-style pattern matching: "*" matches any characters, case-insensitive
    private func matchGlob(pattern: String, string: String) -> Bool {
        let p = pattern.lowercased()
        let s = string.lowercased()

        if !p.contains("*") {
            return p == s
        }

        // Simple glob: prefix*, *suffix, *contains*
        if p.hasPrefix("*") && p.hasSuffix("*") {
            let inner = String(p.dropFirst().dropLast())
            return s.contains(inner)
        } else if p.hasPrefix("*") {
            let suffix = String(p.dropFirst())
            return s.hasSuffix(suffix)
        } else if p.hasSuffix("*") {
            let prefix = String(p.dropLast())
            return s.hasPrefix(prefix)
        }

        return p == s
    }

    // MARK: - Reset

    func reset() {
        lock.lock()
        screenIndex = nil
        screenCache.removeAll()
        flowCache.removeAll()
        nestingDepth = 0
        lock.unlock()
        disableNavigationInterception()
    }
}
