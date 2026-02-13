import Foundation
import FirebaseFirestore

/// Manages remote config, flags, experiments, and paywalls from Firestore.
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

    // MARK: - Fetch from Firestore

    func fetchConfigs() {
        guard let firestorePath else {
            Log.warning("No Firestore path available — serving cached config only")
            return
        }

        let db = Firestore.firestore()
        let basePath = "\(firestorePath)/config"

        // Fetch all 4 config documents in parallel
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
        Log.debug("Loaded cached configs from disk")
    }

    private func parsePaywalls(_ data: [String: Any]) {
        // Each key in the document is a paywall ID mapping to its config
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

struct ExperimentVariant: Codable {
    let id: String
    let weight: Double
    let payload: [String: AnyCodable]?
}
