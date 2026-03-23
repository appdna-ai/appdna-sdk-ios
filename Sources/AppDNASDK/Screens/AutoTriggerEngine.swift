import Foundation

/// Evaluates trigger rules from ScreenIndex entries on each event, session start, and screen transition.
internal class AutoTriggerEngine {

    private var impressionCounts: [String: Int] = [:]  // screenId -> count
    private var lastShownTimes: [String: Date] = [:]   // screenId -> last shown timestamp
    private var shownThisSession: Set<String> = []

    func resetSession() {
        shownThisSession.removeAll()
    }

    /// Evaluate all triggers for a given event. Returns the screen ID to show (highest priority), or nil.
    func evaluate(
        entries: [ScreenIndexEntry],
        event: String,
        properties: [String: Any]?,
        userTraits: [String: Any],
        sessionCount: Int,
        daysSinceInstall: Int,
        currentScreenName: String?
    ) -> String? {
        let now = Date()

        let matching = entries
            .filter { entry in
                evaluateEntry(entry, event: event, properties: properties, userTraits: userTraits,
                             sessionCount: sessionCount, daysSinceInstall: daysSinceInstall,
                             currentScreenName: currentScreenName, now: now)
            }
            .sorted { ($0.priority ?? 0) > ($1.priority ?? 0) }

        if let best = matching.first {
            // Mark as shown
            impressionCounts[best.id, default: 0] += 1
            lastShownTimes[best.id] = now
            shownThisSession.insert(best.id)
            return best.id
        }

        return nil
    }

    private func evaluateEntry(
        _ entry: ScreenIndexEntry,
        event: String,
        properties: [String: Any]?,
        userTraits: [String: Any],
        sessionCount: Int,
        daysSinceInstall: Int,
        currentScreenName: String?,
        now: Date
    ) -> Bool {
        // Check scheduling
        if let startDate = entry.start_date,
           let date = ISO8601DateFormatter().date(from: startDate),
           date > now { return false }
        if let endDate = entry.end_date,
           let date = ISO8601DateFormatter().date(from: endDate),
           date < now { return false }

        // Check audience rules
        if let audienceRules = entry.audience_rules {
            if !AudienceRuleEvaluator.evaluate(rules: audienceRules, userTraits: userTraits) {
                return false
            }
        }

        guard let triggerRules = entry.trigger_rules else { return false }

        // Check frequency
        if let frequency = triggerRules.frequency {
            if let maxImpressions = frequency.max_impressions,
               (impressionCounts[entry.id] ?? 0) >= maxImpressions {
                return false
            }
            if frequency.once_per_session == true, shownThisSession.contains(entry.id) {
                return false
            }
            if let cooldownHours = frequency.cooldown_hours,
               let lastShown = lastShownTimes[entry.id] {
                let cooldownSeconds = Double(cooldownHours) * 3600
                if now.timeIntervalSince(lastShown) < cooldownSeconds {
                    return false
                }
            }
        }

        var anyTriggerMatched = false

        // Event triggers
        if let events = triggerRules.events {
            for trigger in events {
                if trigger.event_name == event {
                    if let conditions = trigger.conditions, let props = properties {
                        let allMatch = conditions.allSatisfy { cond in
                            ConditionEvaluator.valuesEqual(props[cond.field], cond.value?.value)
                        }
                        if allMatch { anyTriggerMatched = true }
                    } else {
                        anyTriggerMatched = true
                    }
                }
            }
        }

        // Session count triggers
        if let sessionTrigger = triggerRules.session_count {
            if let exact = sessionTrigger.exact, sessionCount == exact { anyTriggerMatched = true }
            if let min = sessionTrigger.min, let max = sessionTrigger.max,
               sessionCount >= min && sessionCount <= max { anyTriggerMatched = true }
            if sessionTrigger.exact == nil && sessionTrigger.max == nil,
               let min = sessionTrigger.min, sessionCount >= min { anyTriggerMatched = true }
        }

        // Days since install triggers
        if let timeTrigger = triggerRules.days_since_install {
            if let min = timeTrigger.min, daysSinceInstall >= min {
                if let max = timeTrigger.max {
                    if daysSinceInstall <= max { anyTriggerMatched = true }
                } else {
                    anyTriggerMatched = true
                }
            }
        }

        // Screen-based triggers
        if let onScreen = triggerRules.on_screen, let current = currentScreenName {
            if matchGlob(pattern: onScreen, string: current) {
                anyTriggerMatched = true
            }
        }

        // User trait triggers
        if let traitConditions = triggerRules.user_traits, !traitConditions.isEmpty {
            let allTraitsMatch = traitConditions.allSatisfy { cond in
                let traitValue = userTraits[cond.trait]
                switch cond.operator {
                case "equals", "eq": return ConditionEvaluator.valuesEqual(traitValue, cond.value?.value)
                case "not_equals", "neq": return !ConditionEvaluator.valuesEqual(traitValue, cond.value?.value)
                case "exists": return traitValue != nil
                default: return true
                }
            }
            if allTraitsMatch { anyTriggerMatched = true }
        }

        return anyTriggerMatched
    }

    private func matchGlob(pattern: String, string: String) -> Bool {
        let p = pattern.lowercased()
        let s = string.lowercased()
        if !p.contains("*") { return p == s }
        if p.hasPrefix("*") && p.hasSuffix("*") { return s.contains(String(p.dropFirst().dropLast())) }
        if p.hasPrefix("*") { return s.hasSuffix(String(p.dropFirst())) }
        if p.hasSuffix("*") { return s.hasPrefix(String(p.dropLast())) }
        return p == s
    }
}
