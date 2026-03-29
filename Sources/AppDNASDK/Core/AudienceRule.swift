import Foundation

// MARK: - Audience targeting models for SPEC-089c (SDUI engine prerequisite)

public struct AudienceRule: Codable {
    public let trait: String?
    public let `operator`: String?  // "equals", "not_equals", "gt", "lt", "contains", "exists"
    public let value: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case trait
        case `operator` = "operator"
        case value
    }
}

public struct AudienceRuleSet: Codable {
    public let priority: Int?
    public let conditions: [AudienceRule]?
    public let match_mode: String?  // "all" or "any", default "all"
}

internal enum AudienceRuleEvaluator {

    static func evaluate(rules: AudienceRuleSet?, userTraits: [String: Any]) -> Bool {
        guard let rules = rules, let conditions = rules.conditions, !conditions.isEmpty else {
            return true  // No rules = pass
        }

        let matchAll = (rules.match_mode ?? "all") == "all"

        if matchAll {
            return conditions.allSatisfy { evaluateRule($0, userTraits: userTraits) }
        } else {
            return conditions.contains { evaluateRule($0, userTraits: userTraits) }
        }
    }

    static func evaluate(ruleArray: [AudienceRule]?, userTraits: [String: Any]) -> Bool {
        guard let rules = ruleArray, !rules.isEmpty else { return true }
        return rules.allSatisfy { evaluateRule($0, userTraits: userTraits) }
    }

    private static func evaluateRule(_ rule: AudienceRule, userTraits: [String: Any]) -> Bool {
        guard let traitKey = rule.trait else { return true }
        let traitValue = userTraits[traitKey]

        switch rule.operator ?? "equals" {
        case "equals", "eq":
            return ConditionEvaluator.valuesEqual(traitValue, rule.value?.value)
        case "not_equals", "neq":
            return !ConditionEvaluator.valuesEqual(traitValue, rule.value?.value)
        case "gt":
            return ConditionEvaluator.compareNumeric(traitValue, rule.value?.value) == .orderedDescending
        case "gte":
            let cmp = ConditionEvaluator.compareNumeric(traitValue, rule.value?.value)
            return cmp == .orderedDescending || cmp == .orderedSame
        case "lt":
            return ConditionEvaluator.compareNumeric(traitValue, rule.value?.value) == .orderedAscending
        case "lte":
            let cmp = ConditionEvaluator.compareNumeric(traitValue, rule.value?.value)
            return cmp == .orderedAscending || cmp == .orderedSame
        case "contains":
            if let str = traitValue as? String, let search = rule.value?.value as? String {
                return str.lowercased().contains(search.lowercased())
            }
            if let arr = traitValue as? [String], let search = rule.value?.value as? String {
                return arr.contains(search)
            }
            return false
        case "exists":
            return traitValue != nil
        case "in":
            if let arr = rule.value?.value as? [String], let val = traitValue as? String {
                return arr.contains(val)
            }
            return false
        case "not_in":
            if let arr = rule.value?.value as? [String], let val = traitValue as? String {
                return !arr.contains(val)
            }
            return true
        default:
            return true
        }
    }
}
