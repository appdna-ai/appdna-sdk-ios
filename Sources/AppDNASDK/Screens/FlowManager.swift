import Foundation
import Combine

/// Manages multi-screen flow navigation with back stack, navigation rules, and response accumulation.
internal class FlowManager: ObservableObject {
    @Published var currentScreenIndex: Int = 0
    @Published var navigationStack: [String] = []

    let flowConfig: FlowConfig
    let screens: [String: ScreenConfig]
    var responses: [String: Any] = [:]
    var screensViewed: [String] = []
    let startTime = Date()

    var onComplete: ((FlowResult) -> Void)?

    private var flowScreens: [FlowScreenRef] { flowConfig.screens ?? [] }

    var currentScreen: ScreenConfig? {
        guard currentScreenIndex < flowScreens.count else { return nil }
        guard let screenId = flowScreens[currentScreenIndex].screen_id else { return nil }
        return screens[screenId]
    }

    var currentScreenId: String? {
        guard currentScreenIndex < flowScreens.count else { return nil }
        return flowScreens[currentScreenIndex].screen_id
    }

    init(flowConfig: FlowConfig, screens: [String: ScreenConfig]) {
        self.flowConfig = flowConfig
        self.screens = screens

        // Start from the configured start screen
        if let startIdx = flowScreens.firstIndex(where: { $0.screen_id == flowConfig.start_screen_id }) {
            self.currentScreenIndex = startIdx
        }

        if let firstScreenId = currentScreenId {
            screensViewed.append(firstScreenId)
        }
    }

    func handleAction(_ action: SectionAction) {
        switch action {
        case .next:
            advanceToNextScreen()
        case .back:
            navigateBack()
        case .dismiss:
            dismissFlow()
        case .navigate(let screenId):
            navigateToScreen(screenId)
        default:
            break // Other actions handled by parent
        }
    }

    private func advanceToNextScreen() {
        guard currentScreenIndex < flowScreens.count else {
            completeFlow()
            return
        }

        let currentRef = flowScreens[currentScreenIndex]

        // Evaluate navigation rules in array order, first match wins (§16.15)
        for rule in currentRef.navigation_rules ?? [] {
            if evaluateCondition(rule) {
                switch rule.target ?? "next" {
                case "next":
                    moveToNext()
                case "end":
                    completeFlow()
                default:
                    navigateToScreen(rule.target ?? "next")
                }
                return
            }
        }

        // Default: advance to next
        moveToNext()
    }

    private func moveToNext() {
        if currentScreenIndex + 1 < flowScreens.count {
            if let screenId = currentScreenId {
                navigationStack.append(screenId)
            }
            currentScreenIndex += 1
            if let screenId = currentScreenId {
                screensViewed.append(screenId)
            }
        } else {
            completeFlow()
        }
    }

    private func navigateBack() {
        if let previousScreenId = navigationStack.popLast() {
            if let index = flowScreens.firstIndex(where: { $0.screen_id == previousScreenId }) {
                currentScreenIndex = index
            }
        }
    }

    private func navigateToScreen(_ screenId: String) {
        if let index = flowScreens.firstIndex(where: { $0.screen_id == screenId }) {
            if let currentId = currentScreenId {
                navigationStack.append(currentId)
            }
            currentScreenIndex = index
            screensViewed.append(screenId)
        }
    }

    private func completeFlow() {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let result = FlowResult(
            flowId: flowConfig.id ?? "",
            completed: true,
            lastScreenId: currentScreenId ?? "",
            responses: responses,
            screensViewed: screensViewed,
            duration_ms: duration
        )
        onComplete?(result)
    }

    func dismissFlow() {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let result = FlowResult(
            flowId: flowConfig.id ?? "",
            completed: false,
            lastScreenId: currentScreenId ?? "",
            responses: responses,
            screensViewed: screensViewed,
            duration_ms: duration
        )
        onComplete?(result)
    }

    private func evaluateCondition(_ rule: NavigationRule) -> Bool {
        let context = ["responses": responses]
        return ConditionEvaluator.evaluateCondition(
            type: rule.condition ?? "always",
            variable: rule.variable,
            value: rule.value?.value,
            context: context
        )
    }

    func mergeResponses(_ newResponses: [String: Any]) {
        for (key, value) in newResponses {
            responses[key] = value
        }
    }
}
