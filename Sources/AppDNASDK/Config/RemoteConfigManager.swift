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

    /// Shared JSON decoder for all config parsing.
    private static let snakeCaseDecoder = JSONDecoder()

    /// Recursively sanitize Firestore dictionaries: coerce string "true"/"false" → Bool,
    /// string numbers → NSNumber so JSONDecoder doesn't fail on type mismatches.
    private static func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { sanitize($0) }
        }
        if let arr = value as? [Any] {
            return arr.map { sanitize($0) }
        }
        if let str = value as? String {
            let lower = str.lowercased()
            if lower == "true" { return true }
            if lower == "false" { return false }
            // Coerce numeric strings (but not hex colors or UUIDs)
            if !str.hasPrefix("#"), !str.contains("-"),
               str.count < 20, let num = Double(str) {
                if num == num.rounded() && !str.contains(".") { return Int(num) }
                return num
            }
        }
        return value
    }

    /// Encode a Firestore dictionary to JSON Data, sanitizing type mismatches first.
    private static func sanitizedJSONData(_ dict: [String: Any]) throws -> Data {
        let clean = sanitize(dict) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: clean)
    }

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

    // MARK: - Bundled config (offline-first)

    /// Load config from the bundled appdna-config.json embedded in the app binary.
    /// Only populates empty caches — remote and cached data take priority.
    func loadBundledConfig(_ json: [String: Any]) {
        queue.sync {
            // Paywalls
            if self.paywalls.isEmpty, let data = json["paywalls"] as? [String: Any], !data.isEmpty {
                self.parsePaywalls(data)
                Log.debug("Loaded paywalls from bundled config")
            }
            // Onboarding
            if self.onboardingFlows.isEmpty, let data = json["onboarding"] as? [String: Any], !data.isEmpty {
                self.parseOnboarding(data)
                Log.debug("Loaded onboarding from bundled config")
            }
            // Experiments
            if self.experiments.isEmpty, let data = json["experiments"] as? [String: Any], !data.isEmpty {
                self.parseExperiments(data)
                Log.debug("Loaded experiments from bundled config")
            }
            // Messages
            if self.messages.isEmpty, let data = json["messages"] as? [String: Any], !data.isEmpty {
                self.parseMessages(data)
                Log.debug("Loaded messages from bundled config")
            }
            // Surveys
            if self.surveys.isEmpty, let data = json["surveys"] as? [String: Any], !data.isEmpty {
                self.parseSurveys(data)
                Log.debug("Loaded surveys from bundled config")
            }
            // Flags / remote config
            if self.flags.isEmpty {
                if let data = json["remote_config"] as? [String: Any], !data.isEmpty {
                    self.flags = data
                    Log.debug("Loaded remote_config from bundled config")
                } else if let data = json["feature_flags"] as? [String: Any], !data.isEmpty {
                    self.flags = data
                    Log.debug("Loaded feature_flags from bundled config")
                }
            }
            // Screen index
            if let data = json["screen_index"] as? [String: Any], !data.isEmpty {
                self.parseScreenIndex(data)
                Log.debug("Loaded screen_index from bundled config")
            }
        }
    }

    // MARK: - Onboarding (v0.2)

    /// Get all onboarding flows (for audience-based selection).
    func getAllOnboardingFlows() -> [String: OnboardingFlowConfig] {
        queue.sync { onboardingFlows }
    }

    /// Get all paywall configs (for audience-based selection).
    func getAllPaywalls() -> [String: PaywallConfig] {
        queue.sync { paywalls }
    }

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

    // MARK: - SPEC-067: Force Refresh

    /// Force an immediate config refresh, bypassing the cache TTL.
    /// Use this when you need configs to update immediately (e.g., after a user action).
    func forceRefresh() {
        Log.info("Force refreshing remote config (bypassing TTL)")
        fetchConfigs()
    }

    // MARK: - Fetch from Firestore

    func fetchConfigs() {
        guard let firestorePath else {
            Log.warning("No Firestore path available — serving cached config only")
            return
        }

        guard let db = AppDNA.firestoreDB else {
            Log.warning("Firestore not initialized — serving cached config only")
            return
        }
        let basePath = "\(firestorePath)/config"

        // Fetch all config documents in parallel.
        // For paywalls, onboarding, and surveys: prefer per-item docs (via index)
        // to avoid the 1MB mega-doc limit. Fall back to legacy mega-doc if no index.
        let group = DispatchGroup()

        // Paywalls: index → per-item docs, fallback → mega-doc
        group.enter()
        self.fetchViaIndex(
            db: db, basePath: basePath,
            indexPath: "paywall_index", indexKey: "paywalls",
            itemCollection: "paywalls",
            megaDocPath: "paywalls",
            parseItem: { [weak self] id, data in self?.parseSinglePaywall(id: id, data: data) },
            parseMegaDoc: { [weak self] data in self?.parsePaywalls(data) },
            onComplete: { group.leave() }
        )

        // Onboarding: index → per-item docs, fallback → mega-doc
        group.enter()
        self.fetchViaIndex(
            db: db, basePath: basePath,
            indexPath: "onboarding_index", indexKey: "flows",
            itemCollection: "onboarding",
            megaDocPath: "onboarding",
            parseItem: { [weak self] id, data in self?.parseSingleOnboardingFlow(id: id, data: data) },
            parseMegaDoc: { [weak self] data in self?.parseOnboarding(data) },
            extraIndexParse: { [weak self] indexData in
                // Extract active_flow_id from the index
                if let activeId = indexData["active_flow_id"] as? String {
                    self?.queue.async { self?.activeOnboardingFlowId = activeId }
                }
            },
            onComplete: { group.leave() }
        )

        // Surveys: index → per-item docs, fallback → mega-doc
        group.enter()
        self.fetchViaIndex(
            db: db, basePath: basePath,
            indexPath: "survey_index", indexKey: "surveys",
            itemCollection: "surveys",
            megaDocPath: "surveys",
            parseItem: { [weak self] id, data in self?.parseSingleSurvey(id: id, data: data) },
            parseMegaDoc: { [weak self] data in self?.parseSurveys(data) },
            onComplete: { group.leave() }
        )

        // Experiments — lightweight, keep mega-doc pattern
        group.enter()
        db.document("\(basePath)/experiments").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseExperiments(data)
            } else if let error {
                Log.error("Failed to fetch experiments config: \(error.localizedDescription)")
            }
        }

        // Flags — lightweight, keep mega-doc pattern
        group.enter()
        db.document("\(basePath)/flags").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                let unwrapped = (data["flags"] as? [String: Any]) ?? data
                self?.queue.async { self?.flags = unwrapped }
                if let jsonData = try? JSONSerialization.data(withJSONObject: unwrapped) {
                    self?.configCache.storeFlags(jsonData)
                }
            } else if let error {
                Log.error("Failed to fetch flags config: \(error.localizedDescription)")
            }
        }

        // Flows (legacy zero-code) — lightweight, keep mega-doc
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

        // In-app messages — lightweight, keep mega-doc
        group.enter()
        db.document("\(basePath)/messages").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseMessages(data)
            } else if let error {
                Log.error("Failed to fetch messages config: \(error.localizedDescription)")
            }
        }

        // SPEC-089c: Screen index for server-driven UI
        group.enter()
        db.document("\(basePath)/screen_index").getDocument { [weak self] snapshot, error in
            defer { group.leave() }
            if let data = snapshot?.data() {
                self?.parseScreenIndex(data)
            } else if let error {
                Log.debug("No screen_index config: \(error.localizedDescription)")
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
        // Firestore doc structure: { "paywalls": { "uuid1": {...}, "uuid2": {...} } }
        // Unwrap the "paywalls" wrapper if present, otherwise treat data as flat map
        let paywallMap = (data["paywalls"] as? [String: Any]) ?? data
        var parsed: [String: PaywallConfig] = [:]
        for (key, value) in paywallMap {
            guard let dict = value as? [String: Any] else { continue }
            do {
                let jsonData = try Self.sanitizedJSONData(dict)
                let config = try Self.snakeCaseDecoder.decode(PaywallConfig.self, from: jsonData)
                parsed[key] = config
            } catch let decodingError as DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let ctx):
                    Log.error("Paywall '\(key)' decode: missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                case .typeMismatch(let type, let ctx):
                    Log.error("Paywall '\(key)' decode: type mismatch for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)")
                case .valueNotFound(let type, let ctx):
                    Log.error("Paywall '\(key)' decode: null value for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                case .dataCorrupted(let ctx):
                    Log.error("Paywall '\(key)' decode: corrupted at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)")
                @unknown default:
                    Log.error("Paywall '\(key)' decode: \(decodingError)")
                }
            } catch {
                Log.error("Failed to decode paywall '\(key)': \(error)")
            }
        }
        queue.async { self.paywalls = parsed }

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            configCache.storePaywalls(jsonData)
        }
    }

    private func parseExperiments(_ data: [String: Any]) {
        // Firestore doc structure: { "experiments": { "uuid1": {...}, "uuid2": {...} } }
        let experimentsMap = (data["experiments"] as? [String: Any]) ?? data
        var parsed: [String: ExperimentConfig] = [:]
        for (key, value) in experimentsMap {
            guard let dict = value as? [String: Any] else { continue }
            do {
                let jsonData = try Self.sanitizedJSONData(dict)
                let config = try Self.snakeCaseDecoder.decode(ExperimentConfig.self, from: jsonData)
                parsed[key] = config
            } catch {
                Log.error("Failed to decode experiment '\(key)': \(error.localizedDescription)")
            }
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
                guard let dict = value as? [String: Any] else { continue }
                do {
                    let jsonData = try Self.sanitizedJSONData(dict)
                    let config = try Self.snakeCaseDecoder.decode(OnboardingFlowConfig.self, from: jsonData)
                    parsed[key] = config
                } catch let decodingError as DecodingError {
                    switch decodingError {
                    case .keyNotFound(let codingKey, let ctx):
                        Log.error("Onboarding '\(key)' decode: missing key '\(codingKey.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                    case .typeMismatch(let type, let ctx):
                        Log.error("Onboarding '\(key)' decode: type mismatch for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)")
                    case .valueNotFound(let type, let ctx):
                        Log.error("Onboarding '\(key)' decode: null value for \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
                    case .dataCorrupted(let ctx):
                        Log.error("Onboarding '\(key)' decode: corrupted at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)")
                    @unknown default:
                        Log.error("Onboarding '\(key)' decode: \(decodingError)")
                    }
                } catch {
                    Log.error("Failed to decode onboarding flow '\(key)': \(error)")
                }
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
                  let jsonData = try? Self.sanitizedJSONData(dict),
                  let config = try? Self.snakeCaseDecoder.decode(MessageConfig.self, from: jsonData) else {
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
                  let jsonData = try? Self.sanitizedJSONData(dict),
                  let config = try? Self.snakeCaseDecoder.decode(SurveyConfig.self, from: jsonData) else {
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

    // MARK: - SPEC-089c: Screen Index

    private func parseScreenIndex(_ data: [String: Any]) {
        do {
            let jsonData = try Self.sanitizedJSONData(data)
            let index = try Self.snakeCaseDecoder.decode(ScreenIndex.self, from: jsonData)
            ScreenManager.shared.updateIndex(index)
            Log.info("Screen index loaded: \(index.screens?.count ?? 0) screens, \(index.flows?.count ?? 0) flows, \(index.slots?.count ?? 0) slots")
        } catch {
            Log.error("Failed to parse screen_index: \(error)")
        }
    }

    // MARK: - Per-item fetch via index (enterprise-grade)

    /// Generic helper: try to load items via a lightweight index document.
    /// If the index exists, fan out to individual per-item documents.
    /// If no index, fall back to the legacy mega-document.
    ///
    /// This avoids the 1MB Firestore limit for config types with many items
    /// (paywalls, onboarding flows, surveys) while staying backward-compatible
    /// with older backends that only write the mega-doc.
    private func fetchViaIndex(
        db: Firestore,
        basePath: String,
        indexPath: String,
        indexKey: String,
        itemCollection: String,
        megaDocPath: String,
        parseItem: @escaping (String, [String: Any]) -> Void,
        parseMegaDoc: @escaping ([String: Any]) -> Void,
        extraIndexParse: (([String: Any]) -> Void)? = nil,
        onComplete: @escaping () -> Void
    ) {
        db.document("\(basePath)/\(indexPath)").getDocument { [weak self] snapshot, error in
            guard let self else { onComplete(); return }

            if let indexData = snapshot?.data(),
               let itemsMap = indexData[indexKey] as? [String: Any],
               !itemsMap.isEmpty {
                // Index exists — fetch individual docs in parallel
                Log.debug("[\(indexPath)] Found index with \(itemsMap.count) items, fetching individually")
                extraIndexParse?(indexData)

                let itemGroup = DispatchGroup()
                for itemId in itemsMap.keys {
                    itemGroup.enter()
                    db.document("\(basePath)/\(itemCollection)/\(itemId)").getDocument { itemSnapshot, itemError in
                        defer { itemGroup.leave() }
                        if let itemData = itemSnapshot?.data() {
                            parseItem(itemId, itemData)
                        } else if let itemError {
                            Log.warning("[\(indexPath)] Failed to fetch item \(itemId): \(itemError.localizedDescription)")
                        }
                    }
                }
                itemGroup.notify(queue: .global()) {
                    onComplete()
                }
            } else {
                // No index — fall back to legacy mega-doc
                Log.debug("[\(indexPath)] No index found, falling back to mega-doc \(megaDocPath)")
                db.document("\(basePath)/\(megaDocPath)").getDocument { megaSnapshot, megaError in
                    defer { onComplete() }
                    if let data = megaSnapshot?.data() {
                        parseMegaDoc(data)
                    } else if let megaError {
                        Log.error("Failed to fetch \(megaDocPath) config: \(megaError.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Per-item parsers (for index-based fetching)

    private func parseSinglePaywall(id: String, data: [String: Any]) {
        do {
            let jsonData = try Self.sanitizedJSONData(data)
            let config = try Self.snakeCaseDecoder.decode(PaywallConfig.self, from: jsonData)
            queue.async { self.paywalls[id] = config }
        } catch {
            Log.error("Failed to decode individual paywall '\(id)': \(error)")
        }
    }

    private func parseSingleOnboardingFlow(id: String, data: [String: Any]) {
        do {
            let jsonData = try Self.sanitizedJSONData(data)
            let config = try Self.snakeCaseDecoder.decode(OnboardingFlowConfig.self, from: jsonData)
            queue.async { self.onboardingFlows[id] = config }
        } catch {
            Log.error("Failed to decode individual onboarding flow '\(id)': \(error)")
        }
    }

    private func parseSingleSurvey(id: String, data: [String: Any]) {
        do {
            let jsonData = try Self.sanitizedJSONData(data)
            let config = try Self.snakeCaseDecoder.decode(SurveyConfig.self, from: jsonData)
            queue.async {
                self.surveys[id] = config
                self.surveyUpdateHandler?(self.surveys)
            }
        } catch {
            Log.error("Failed to decode individual survey '\(id)': \(error)")
        }
    }

    /// Fetch a single paywall config on-demand by ID (for lazy loading).
    func fetchPaywallConfig(id: String, completion: @escaping (PaywallConfig?) -> Void) {
        guard let firestorePath else { completion(nil); return }
        guard let db = AppDNA.firestoreDB else { completion(nil); return }
        let basePath = "\(firestorePath)/config"
        db.document("\(basePath)/paywalls/\(id)").getDocument { [weak self] snapshot, error in
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            do {
                let jsonData = try Self.sanitizedJSONData(data)
                let config = try Self.snakeCaseDecoder.decode(PaywallConfig.self, from: jsonData)
                self?.queue.async { self?.paywalls[id] = config }
                completion(config)
            } catch {
                Log.error("Failed to decode paywall '\(id)': \(error)")
                completion(nil)
            }
        }
    }

    /// Fetch a single onboarding flow on-demand by ID (for lazy loading).
    func fetchOnboardingConfig(id: String, completion: @escaping (OnboardingFlowConfig?) -> Void) {
        guard let firestorePath else { completion(nil); return }
        guard let db = AppDNA.firestoreDB else { completion(nil); return }
        let basePath = "\(firestorePath)/config"
        db.document("\(basePath)/onboarding/\(id)").getDocument { [weak self] snapshot, error in
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            do {
                let jsonData = try Self.sanitizedJSONData(data)
                let config = try Self.snakeCaseDecoder.decode(OnboardingFlowConfig.self, from: jsonData)
                self?.queue.async { self?.onboardingFlows[id] = config }
                completion(config)
            } catch {
                Log.error("Failed to decode onboarding flow '\(id)': \(error)")
                completion(nil)
            }
        }
    }

    /// Fetch a single screen config on-demand by ID.
    func fetchScreenConfig(screenId: String, completion: @escaping (ScreenConfig?) -> Void) {
        guard let firestorePath else {
            completion(nil)
            return
        }
        guard let db = AppDNA.firestoreDB else { completion(nil); return }
        let basePath = "\(firestorePath)/config"
        // screens/{screenId} is a subcollection document under the screen_index doc
        db.document("\(basePath)/screen_index/screens/\(screenId)").getDocument { snapshot, error in
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            do {
                let jsonData = try Self.sanitizedJSONData(data)
                let wrapper = try Self.snakeCaseDecoder.decode(ScreenFirestoreWrapper.self, from: jsonData)
                let config = wrapper.config
                ScreenManager.shared.cacheScreen(screenId, config: config)
                completion(config)
            } catch {
                // Try parsing the data directly as a ScreenConfig
                do {
                    let jsonData = try Self.sanitizedJSONData(data)
                    let config = try Self.snakeCaseDecoder.decode(ScreenConfig.self, from: jsonData)
                    ScreenManager.shared.cacheScreen(screenId, config: config)
                    completion(config)
                } catch {
                    Log.error("Failed to parse screen config \(screenId): \(error)")
                    completion(nil)
                }
            }
        }
    }
}

/// Wrapper for Firestore screen document (has `config` field inside).
private struct ScreenFirestoreWrapper: Codable {
    let config: ScreenConfig
}

// MARK: - Experiment config model

struct ExperimentConfig: Codable {
    let id: String?
    let name: String?
    let status: String? // "running", "paused", "completed"
    let salt: String?
    let platforms: [String]?
    let variants: [ExperimentVariant]?
    let segments: [String]?
}

public struct ExperimentVariant: Codable {
    let id: String?
    let weight: Double?
    let payload: [String: AnyCodable]?
}
