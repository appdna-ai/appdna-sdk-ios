import Foundation

/// Pure onboarding advance state machine.
///
/// WHY this exists: the routing surface (next_step_rules → step / paywall_trigger / analytics_event /
/// end, plus hook-result handling and skip-to) is the most bug-prone code in the onboarding module,
/// and it lived entirely in private methods on the SwiftUI `OnboardingFlowHost`. Nothing outside the
/// SwiftUI runtime could reach it, so it had no test seam and the shared cross-platform fixtures could
/// only assert against a re-implementation of it. The logic below is a MOVE of the host's
/// `advanceOrComplete` / `skipToStep` / `mergeData` / `handleHookResult` / `evaluateRule` /
/// `evaluateCondition`; the host now computes an ``Outcome`` here and executes it.
///
/// Mirrors Android `OnboardingAdvance.kt` (`internal object OnboardingAdvance`) so the two platforms
/// read side by side: same outcome shape (navigation + responses + events + banner).
///
/// Everything here is pure: no SwiftUI state, no event tracker, no delegate. Side effects the host
/// must perform (image-preloading navigation, history push, analytics, flow completion, paywall
/// presentation) are DESCRIBED by the returned ``Outcome`` instead of performed.
///
/// KNOWN divergence from Android, preserved deliberately (this is a behaviour-preserving extraction,
/// not a merge): iOS does not emit Android's `onboarding_flow_completed_via_fallback` event, and iOS
/// does not carry Android's `permission` / `screen` / `sub_flow` graph-node completion markers — iOS
/// routes those elsewhere. iOS also pushes navigation history inside `navigate(to:)` (after the
/// decision), so the outcome carries no `historyPush` list; `previousStepId` is passed IN instead.
enum OnboardingAdvance {

    /// An analytics event the caller must hand to its `EventTracker`, in list order.
    struct TrackedEvent {
        let name: String
        let props: [String: Any]
    }

    /// Banner state the caller must raise (error pill / success pill).
    enum Banner {
        case error(String)
        case success(String)
    }

    /// Where the flow goes next.
    enum Navigation {
        /// Move to `flow.steps[index]` (host routes through `navigate(to:)` → image preload + history).
        case goToIndex(Int)
        /// Finish the flow, handing `responses` to `onFlowCompleted`.
        case completeFlow(responses: [String: Any])
        /// Hand a `paywall_trigger` graph node to the paywall bridge.
        case presentPaywallTrigger(nodeId: String)
        /// Remain on the current step (hook returned `.block` / `.stay`).
        case stay
    }

    struct Outcome {
        let navigation: Navigation
        /// The step responses after any hook-driven merge.
        let responses: [String: Any]
        /// True only when a hook actually merged data — the host writes `responses` back only then, so
        /// a `.block` / `.stay` / plain advance does not churn SwiftUI state (matches pre-extraction).
        var responsesChanged: Bool = false
        /// Hook-computed data the host must persist via `SessionDataStore.mergeComputedData`.
        var computedData: [String: Any]?
        var events: [TrackedEvent] = []
        var banner: Banner?
    }

    /// The event emitted when a `skip_to` / `skip_to_with_data` step advance is APPLIED.
    ///
    /// NOT `onboarding_step_skipped`: that name is already taken, on BOTH platforms, by the skip
    /// BUTTON (iOS `OnboardingFlowManager.swift:95`, Android `OnboardingFlowManager.kt:90`), with
    /// different props (`{flow_id, step_id, step_index}`) and different meaning (the user declined a
    /// step; the flow still advances sequentially). A `skip_to` is a routing JUMP authored by a hook —
    /// the funnel needs to tell a jumped-over step from an unreached one, and reusing the button's
    /// name would fuse two different funnel facts into one event.
    ///
    /// The name + props are pinned to Android's `STEP_SKIPPED_EVENT`
    /// (`onboarding/OnboardingAdvance.kt:325`, `"step_skipped"`, props
    /// `{flow_id, from_step_id, to_step_id}`) — a divergent spelling would be the same bug in a new
    /// place. `from_step_id` is omitted (not null) when the leaving step can't be resolved, matching
    /// Android's `buildMap` + `fromStepId?.let`.
    static let stepSkippedEvent = "step_skipped"

    // MARK: - Hook result

    /// Fold a delegate/webhook `StepAdvanceResult` into the flow state. Mirrors the old
    /// `OnboardingFlowHost.handleHookResult` exactly.
    static func apply(
        result: StepAdvanceResult,
        flow: OnboardingFlowConfig,
        currentIndex: Int,
        responses: [String: Any],
        configOverrides: [String: StepConfigOverride] = [:],
        previousStepId: String? = nil
    ) -> Outcome {
        let stepId = step(flow, currentIndex)?.id ?? ""

        switch result {
        case .proceed:
            return advance(
                flow: flow, currentIndex: currentIndex, responses: responses,
                configOverrides: configOverrides, previousStepId: previousStepId
            )

        case .proceedWithData(let extraData):
            let merged = mergeData(responses, extraData, forStepId: stepId)
            var out = advance(
                flow: flow, currentIndex: currentIndex, responses: merged,
                configOverrides: configOverrides, previousStepId: previousStepId
            )
            out.responsesChanged = true
            out.computedData = extraData
            return out

        case .block(let message):
            return Outcome(navigation: .stay, responses: responses, banner: .error(message))

        case .stay(let message):
            // Stay on the current step. A non-empty message renders in success styling; nil/empty is
            // truly silent — the host has handled the UI itself.
            var banner: Banner?
            if let msg = message, !msg.isEmpty { banner = .success(msg) }
            return Outcome(navigation: .stay, responses: responses, banner: banner)

        case .skipTo(let targetStepId):
            return skipTo(
                flow: flow, currentIndex: currentIndex, targetStepId: targetStepId,
                responses: responses, configOverrides: configOverrides, previousStepId: previousStepId
            )

        case .skipToWithData(let targetStepId, let extraData):
            let merged = mergeData(responses, extraData, forStepId: stepId)
            var out = skipTo(
                flow: flow, currentIndex: currentIndex, targetStepId: targetStepId,
                responses: merged, configOverrides: configOverrides, previousStepId: previousStepId
            )
            out.responsesChanged = true
            out.computedData = extraData
            return out
        }
    }

    // MARK: - Skip-to

    /// Mirrors the old `skipToStep`. An unknown target falls through to ``advance(flow:currentIndex:responses:configOverrides:previousStepId:)``
    /// (no jump happened → no skip event).
    static func skipTo(
        flow: OnboardingFlowConfig,
        currentIndex: Int,
        targetStepId: String,
        responses: [String: Any],
        configOverrides: [String: StepConfigOverride] = [:],
        previousStepId: String? = nil
    ) -> Outcome {
        guard let targetIndex = flow.steps.firstIndex(where: { $0.id == targetStepId }) else {
            return advance(
                flow: flow, currentIndex: currentIndex, responses: responses,
                configOverrides: configOverrides, previousStepId: previousStepId
            )
        }
        // SPEC-070-B — a skip_to jump used to be analytically INVISIBLE: the flow silently teleported
        // over N steps, so the funnel could not tell a step that was jumped over from one the user
        // never reached. Emit the jump.
        var props: [String: Any] = ["flow_id": flow.id, "to_step_id": targetStepId]
        if let fromStepId = step(flow, currentIndex)?.id {
            props["from_step_id"] = fromStepId
        }
        return Outcome(
            navigation: .goToIndex(targetIndex),
            responses: responses,
            events: [TrackedEvent(name: stepSkippedEvent, props: props)]
        )
    }

    // MARK: - Advance

    /// Mirrors the old `advanceOrComplete`: evaluate the current step's next-step rules, else advance
    /// sequentially / complete.
    static func advance(
        flow: OnboardingFlowConfig,
        currentIndex: Int,
        responses: [String: Any],
        configOverrides: [String: StepConfigOverride] = [:],
        previousStepId: String? = nil
    ) -> Outcome {
        var events: [TrackedEvent] = []
        func outcome(_ nav: Navigation) -> Outcome {
            Outcome(navigation: nav, responses: responses, events: events)
        }

        guard let currentStep = step(flow, currentIndex) else {
            // Out of range — the host never calls this way, but completing beats trapping.
            return outcome(.completeFlow(responses: responses))
        }

        let effectiveConfig = StepConfigOverrideMerger.apply(configOverrides[currentStep.id], to: currentStep.config)

        // Prefer layout.next_step_rules (has Logic-panel conditions) over step-level rules.
        let stepRules = currentStep.next_step_rules ?? []
        let layoutRules = effectiveConfig.next_step_rules ?? []
        let hasLayoutConditions = layoutRules.contains { !($0.conditions?.isEmpty ?? true) }
        let hasStepConditions = stepRules.contains { !($0.conditions?.isEmpty ?? true) }
        let rules: [NextStepRule] = hasLayoutConditions && !hasStepConditions ? layoutRules : stepRules

        if !rules.isEmpty {
            for rule in rules {
                guard evaluateRule(
                    rule, flow: flow, stepId: currentStep.id,
                    responses: responses, previousStepId: previousStepId
                ) else { continue }

                let target = rule.target_step_id
                // Route by graph-node TYPE (short ids like `paywall1` carry no prefix) and by the
                // legacy ID prefix, so both forms route.
                let nodeType = graphNodeType(for: target, flow: flow)

                // analytics_event node — fire event, then follow the downstream edge.
                if target.hasPrefix("analytics_event_") || nodeType == "analytics_event" {
                    let nodeData = resolveGraphNode(target, flow: flow)
                    let eventName = nodeData?["event_name"] as? String ?? "onboarding_analytics"
                    events.append(TrackedEvent(name: eventName, props: [
                        "flow_id": flow.id, "node_id": target, "step_id": currentStep.id,
                    ]))
                    if let nextTarget = nodeData?["next_target"] as? String,
                       let targetIndex = flow.steps.firstIndex(where: { $0.id == nextTarget }) {
                        return outcome(.goToIndex(targetIndex))
                    }
                    // No downstream target — continue to the next rule.
                    continue
                }

                if target.hasPrefix("paywall_trigger_") || nodeType == "paywall_trigger" {
                    return outcome(.presentPaywallTrigger(nodeId: target))
                }

                if target.hasPrefix("end_") || nodeType == "end" {
                    return outcome(.completeFlow(responses: responses))
                }

                if let targetIndex = flow.steps.firstIndex(where: { $0.id == target }) {
                    return outcome(.goToIndex(targetIndex))
                }
                // Unresolvable target — fall through to the next rule (unchanged).
            }
        }

        // Default: sequential advance.
        if currentIndex + 1 >= flow.steps.count {
            return outcome(.completeFlow(responses: responses))
        }
        return outcome(.goToIndex(currentIndex + 1))
    }

    // MARK: - Response merge

    /// Mirrors the old `mergeData`: deep-merge into the step's own response map.
    static func mergeData(
        _ responses: [String: Any],
        _ extraData: [String: Any],
        forStepId stepId: String
    ) -> [String: Any] {
        var out = responses
        if var existing = responses[stepId] as? [String: Any] {
            existing.merge(extraData) { _, new in new }
            out[stepId] = existing
        } else {
            out[stepId] = extraData
        }
        return out
    }

    // MARK: - Graph nodes

    /// Resolve any graph node's data by ID from `graph_nodes`.
    static func resolveGraphNode(_ nodeId: String, flow: OnboardingFlowConfig) -> [String: Any]? {
        if let graphNodes = flow.graph_nodes?.value as? [String: Any],
           let node = graphNodes[nodeId] as? [String: Any] {
            return node
        }
        return nil
    }

    /// Look up a graph node's `type`. Nil when the ID is unknown (legacy flows or real step IDs).
    static func graphNodeType(for nodeId: String, flow: OnboardingFlowConfig) -> String? {
        resolveGraphNode(nodeId, flow: flow)?["type"] as? String
    }

    // MARK: - Rule / condition evaluation

    /// Evaluate whether a navigation rule's conditions are met against the current responses.
    static func evaluateRule(
        _ rule: NextStepRule,
        flow: OnboardingFlowConfig,
        stepId: String,
        responses: [String: Any],
        previousStepId: String?
    ) -> Bool {
        // Prefer `conditions` array, fall back to the single `condition`.
        let conditionList: [Any]
        if let conditions = rule.conditions {
            conditionList = conditions.map { $0.value }
        } else if let condition = rule.condition {
            conditionList = [condition.value]
        } else {
            return true // No condition = always match.
        }

        let logic = rule.logic ?? "and"
        let stepResponses = responses[stepId] as? [String: Any] ?? [:]
        let step = flow.steps.first(where: { $0.id == stepId })

        for cond in conditionList {
            let matches: Bool
            if let condStr = cond as? String {
                matches = condStr == "always"
            } else if let condDict = cond as? [String: Any] {
                matches = evaluateCondition(
                    condDict, responses: stepResponses, step: step, previousStepId: previousStepId
                )
            } else {
                matches = true
            }

            if logic == "or" && matches { return true }
            if logic == "and" && !matches { return false }
        }

        return logic == "and" // All passed for "and", none passed for "or".
    }

    /// Evaluate a single condition dict against a step's responses.
    static func evaluateCondition(
        _ cond: [String: Any],
        responses: [String: Any],
        step: OnboardingStep?,
        previousStepId: String?
    ) -> Bool {
        guard let type = cond["type"] as? String else { return true }
        // Console saves "answer_key"; the SDK also accepts "field" for backward compat.
        let field = cond["answer_key"] as? String ?? cond["field"] as? String ?? ""

        func aliasesForField() -> (idToValue: [String: String], valueToId: [String: String]) {
            optionAliases(forField: field, in: step)
        }

        /// True when `expected` equals `actual` directly OR via the option id↔value alias table.
        func aliasedEquals(expected: String, actual: String) -> Bool {
            if expected == actual { return true }
            let (idToVal, valToId) = aliasesForField()
            if let expectedAsValue = idToVal[expected], expectedAsValue == actual { return true }
            if let actualAsId = valToId[actual], actualAsId == expected { return true }
            return false
        }

        switch type {
        case "always":
            return true
        case "answer_equals":
            let expected = cond["value"]
            let actual = responses[field]
            // Multiselect stores ["opt_2"], not "opt_2".
            if let actualArray = actual as? [String], let expectedStr = expected as? String {
                if actualArray.contains(expectedStr) { return true }
                for item in actualArray where aliasedEquals(expected: expectedStr, actual: item) { return true }
                return false
            }
            if isEqual(actual, expected) { return true }
            if let expectedStr = expected as? String, let actualStr = actual as? String {
                return aliasedEquals(expected: expectedStr, actual: actualStr)
            }
            return false
        case "answer_contains":
            let expected = cond["value"] as? String ?? ""
            let actual = responses[field] as? String ?? ""
            if actual.contains(expected) { return true }
            let (idToVal, _) = aliasesForField()
            if let mapped = idToVal[expected], !mapped.isEmpty {
                return actual.contains(mapped)
            }
            return false
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
            guard let prevId = previousStepId else { return false }
            let expected = cond["value"] as? String ?? ""
            return prevId == expected
        case "previous_step_in":
            guard let prevId = previousStepId else { return false }
            if let ids = cond["previous_step_ids"] as? [String] {
                return ids.contains(prevId)
            }
            if let anyArray = cond["previous_step_ids"] as? [Any] {
                let ids = anyArray.compactMap { $0 as? String }
                return ids.contains(prevId)
            }
            if let csv = cond["value"] as? String {
                let ids = csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return ids.contains(prevId)
            }
            return false
        default:
            return true // Unknown condition type = pass.
        }
    }

    /// Option id↔value aliases for a field on a step. Empty when the field isn't an `input_*` block
    /// with options, so callers naturally no-op.
    static func optionAliases(
        forField field: String,
        in step: OnboardingStep?
    ) -> (idToValue: [String: String], valueToId: [String: String]) {
        guard let step = step else { return ([:], [:]) }
        let blocks: [ContentBlock] = step.config.content_blocks ?? []
        guard let block = blocks.first(where: { $0.field_id == field && $0.type.rawValue.hasPrefix("input_") }),
              let options = block.field_options else {
            return ([:], [:])
        }
        var idToVal: [String: String] = [:]
        var valToId: [String: String] = [:]
        for opt in options {
            let id = opt.id ?? ""
            let val = opt.value ?? id
            if !id.isEmpty && !val.isEmpty {
                idToVal[id] = val
                valToId[val] = id
            }
        }
        return (idToVal, valToId)
    }

    static func isEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        if let aStr = a as? String, let bStr = b as? String { return aStr == bStr }
        if let aNum = a as? Double, let bNum = b as? Double { return aNum == bNum }
        if let aInt = a as? Int, let bInt = b as? Int { return aInt == bInt }
        if let aBool = a as? Bool, let bBool = b as? Bool { return aBool == bBool }
        return String(describing: a) == String(describing: b)
    }

    // MARK: - Helpers

    private static func step(_ flow: OnboardingFlowConfig, _ index: Int) -> OnboardingStep? {
        guard index >= 0, index < flow.steps.count else { return nil }
        return flow.steps[index]
    }
}
