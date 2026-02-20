import Foundation
import FirebaseFirestore

/// Manages remote config, flags, experiments, paywalls, onboarding flows, and messages from Firestore.
/// Uses stale-while-revalidate: always returns cached value, refreshes in background.
final class RemoteConfigManager {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.config")
    private let firestorePath: String?
    private let configCache: ConfigCache
    private let configTTL: TimeInterval
    private weak var eventTracker: EventTracker?

    // In-memory caches
    private var paywalls: [String: PaywallConfig] = [:]
    private var experiments: [String: ExperimentConfig] = [:]
    private var flags: [String: Any] = [:]
    private var flows: [String: Any] = [:]
    private var onboardingFlows: [String: OnboardingFlowConfig] = [:]
    private var activeOnboardingFlowId: String?
    private var messages: [String: MessageConfig] = [:]
    private var surveys: [String: SurveyConfig] = [:]

    /// Called by SurveyManager to get current survey configs.
    private var surveyUpdateHandler: (([String: SurveyConfig]) -> Void)?

    init(firestorePath: String?, configCache: ConfigCache, configTTL: TimeInterval) {
        self.firestorePath = firestorePath
        self.configCache = configCache
        self.configTTL = configTTL

        // Load from disk cache on init
        loadCachedConfigs()
    }

    /// Set the event tracker for auto-tracked config_fetched events.
    func setEventTracker(_ tracker: EventTracker) {
        self.eventTracker = tracker
    }

    // MARK: - Public read methods (synchronous, from in-memory cache)

    func getConfig(key: String) -> Any? {
        queue.sync { flags[key] }
    }

    func getPaywallConfig(id: String) -> PaywallConfig? {
        queue.sync { paywalls[id] }
    }

    func getExperimentConfig(id: String) -> ExperimentConfig? {
        queue.sync { experiments[id] }
    }

    func getAllExperiments() -> [String: ExperimentConfig] {
        queue.sync { experiments }
    }

    func getAllFlags() -> [String: Any] {
        queue.sync { flags }
    }

    func getAllConfig() -> [String: Any] {
        getAllFlags()
    }

    // MARK: - Onboarding (v0.2)

    /// Get an onboarding flow by ID, or the active flow if id is nil.
    func getOnboardingFlow(id: String?) -> OnboardingFlowConfig? {
        queue.sync {
            if let id {
                return onboardingFlows[id]
            }
            guard let activeId = activeOnboardingFlowId else { return nil }
            return onboardingFlows[activeId]
        }
    }

    // MARK: - Messages (v0.2)

    /// Get all active message configs.
    func getActiveMessages() -> [String: MessageConfig] {
        queue.sync { messages }
    }

    // MARK: - Surveys (v0.3)

    /// Get all survey configs.
    func getSurveyConfigs() -> [String: SurveyConfig] {
        queue.sync { surveys }
    }

    /// Register a handler that fires when survey configs are updated.
    func onSurveyConfigsUpdated(_ handler: @escaping ([String: SurveyConfig]) -> Void) {
        self.surveyUpdateHandler = handler
    }

    // MARK: - Fetch from Firestore

    func fetchConfigs() {
        guard let firestorePath else {
            Log.warning("No Firestore path available — serving cached config only")
            return
        }

        let db = Firestore.firestore()
        let basePath = "\(firestorePath)/config"

        // Fetch all 6 config documents in parallel
        let group = DispatchGroup()

        group.enter()
        db.document("\(basePath)/paywalls").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parsePaywalls(data)
            } else if let error {
                Log.error("Failed to fetch paywalls config: \(error.localizedDescription)")
            }
        }

        group.enter()
        db.document("\(basePath)/experiments").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseExperiments(data)
            } else if let error {
                Log.error("Failed to fetch experiments config: \(error.localizedDescription)")
            }
        }

        group.enter()
        db.document("\(basePath)/flags").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.queue.async { self?.flags = data }
                if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
                    self?.configCache.storeFlags(jsonData)
                }
            } else if let error {
                Log.error("Failed to fetch flags config: \(error.localizedDescription)")
            }
        }

        group.enter()
        db.document("\(basePath)/flows").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.queue.async { self?.flows = data }
                if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
                    self?.configCache.storeFlows(jsonData)
                }
            } else if let error {
                Log.error("Failed to fetch flows config: \(error.localizedDescription)")
            }
        }

        // v0.2: Onboarding flows
        group.enter()
        db.document("\(basePath)/onboarding").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseOnboarding(data)
            } else if let error {
                Log.error("Failed to fetch onboarding config: \(error.localizedDescription)")
            }
        }

        // v0.2: In-app messages
        group.enter()
        db.document("\(basePath)/messages").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseMessages(data)
            } else if let error {
                Log.error("Failed to fetch messages config: \(error.localizedDescription)")
            }
        }

        // v0.3: Surveys
        group.enter()
        db.document("\(basePath)/surveys").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseSurveys(data)
            } else if let error {
                Log.error("Failed to fetch surveys config: \(error.localizedDescription)")
            }
        }

        group.notify(queue: .global()) {
            self.configCache.markFetched()
            Log.info("Remote config fetched successfully")
            self.eventTracker?.track(event: "config_fetched", properties: nil)
            NotificationCenter.default.post(name: AppDNA.configUpdated, object: nil)

            // Schedule TTL refresh
            DispatchQueue.global().asyncAfter(deadline: .now() + self.configTTL) { [weak self] in
                if self?.configCache.isStale == true {
                    self?.fetchConfigs()
                }
            }
        }
    }

    // MARK: - Private

    private func loadCachedConfigs() {
        if let data = configCache.loadPaywalls() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsePaywalls(dict)
            }
        }
        if let data = configCache.loadExperiments() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parseExperiments(dict)
            }
        }
        if let data = configCache.loadFlags() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                queue.async { self.flags = dict }
            }
        }
        if let data = configCache.loadFlows() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                queue.async { self.flows = dict }
            }
        }
        if let data = configCache.loadOnboarding() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parseOnboarding(dict)
            }
        }
        if let data = configCache.loadMessages() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parseMessages(dict)
            }
        }
        if let data = configCache.loadSurveys() {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parseSurveys(dict)
            }
        }
        Log.debug("Loaded cached configs from disk")
    }

    private func parsePaywalls(_ data: [String: Any]) {
        var parsed: [String: PaywallConfig] = [:]
        for (key, value) in data {
            guard let dict = value as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let config = try? JSONDecoder().decode(PaywallConfig.self, from: jsonData) else {
                continue
            }
            parsed[key] = config
        }
        queue.async { self.paywalls = parsed }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            configCache.storePaywalls(jsonData)
        }
    }

    private func parseExperiments(_ data: [String: Any]) {
        var parsed: [String: ExperimentConfig] = [:]
        for (key, value) in data {
            guard let dict = value as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let config = try? JSONDecoder().decode(ExperimentConfig.self, from: jsonData) else {
                continue
            }
            parsed[key] = config
        }
        queue.async { self.experiments = parsed }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            configCache.storeExperiments(jsonData)
        }
    }

    private func parseOnboarding(_ data: [String: Any]) {
        // Parse active_flow_id
        let activeId = data["active_flow_id"] as? String

        // Parse flows map
        var parsed: [String: OnboardingFlowConfig] = [:]
        if let flowsDict = data["flows"] as? [String: Any] {
            for (key, value) in flowsDict {
                guard let dict = value as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                      let config = try? JSONDecoder().decode(OnboardingFlowConfig.self, from: jsonData) else {
                    continue
                }
                parsed[key] = config
            }
        }

        queue.async {
            self.onboardingFlows = parsed
            self.activeOnboardingFlowId = activeId
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            configCache.storeOnboarding(jsonData)
        }
    }

    private func parseMessages(_ data: [String: Any]) {
        // Parse messages map (may be nested under "messages" key)
        let messagesDict = data["messages"] as? [String: Any] ?? data
        var parsed: [String: MessageConfig] = [:]
        for (key, value) in messagesDict {
            guard key != "version" else { continue }
            guard let dict = value as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let config = try? JSONDecoder().decode(MessageConfig.self, from: jsonData) else {
                continue
            }
            parsed[key] = config
        }

        queue.async { self.messages = parsed }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            configCache.storeMessages(jsonData)
        }
    }

    private func parseSurveys(_ data: [String: Any]) {
        let surveysDict = data["surveys"] as? [String: Any] ?? data
        var parsed: [String: SurveyConfig] = [:]
        for (key, value) in surveysDict {
            guard key != "version" else { continue }
            guard let dict = value as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let config = try? JSONDecoder().decode(SurveyConfig.self, from: jsonData) else {
                continue
            }
            parsed[key] = config
        }

        queue.async {
            self.surveys = parsed
            self.surveyUpdateHandler?(parsed)
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            configCache.storeSurveys(jsonData)
        }
    }
}

// MARK: - Experiment config model

struct ExperimentConfig: Codable {
    let id: String
    let name: String
    let status: String // "running", "paused", "completed"
    let salt: String
    let platforms: [String]
    let variants: [ExperimentVariant]
    let segments: [String]?
}

public struct ExperimentVariant: Codable {
    let id: String
    let weight: Double
    let payload: [String: AnyCodable]?
}
