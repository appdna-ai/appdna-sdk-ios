import Foundation

/// Manages experiment variant assignment via deterministic MurmurHash3 bucketing.
/// Tracks exposure events once per session per experiment.
final class ExperimentManager {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.experiments")
    private let remoteConfigManager: RemoteConfigManager
    private let identityManager: IdentityManager
    private let eventTracker: EventTracker

    /// Map of experiment IDs to variant IDs for which exposure has been tracked this session.
    private var exposedExperiments: [String: String] = [:]

    init(
        remoteConfigManager: RemoteConfigManager,
        identityManager: IdentityManager,
        eventTracker: EventTracker
    ) {
        self.remoteConfigManager = remoteConfigManager
        self.identityManager = identityManager
        self.eventTracker = eventTracker
    }

    /// Get the variant for an experiment. Returns nil if not eligible.
    /// Auto-tracks exposure event on first call per session.
    func getVariant(experimentId: String) -> String? {
        guard let config = resolveConfig(experimentId: experimentId) else { return nil }

        let identity = identityManager.currentIdentity
        let userId = identity.userId ?? identity.anonId

        // Deterministic bucketing via ExperimentBucketer
        guard let variant = ExperimentBucketer.assignVariant(
            experimentId: experimentId,
            userId: userId,
            salt: config.salt,
            variants: config.variants
        ) else {
            return nil
        }

        // Track exposure (once per session)
        trackExposure(experimentId: experimentId, variant: variant)

        return variant
    }

    /// Check if the user is assigned to a specific variant.
    func isInVariant(experimentId: String, variantId: String) -> Bool {
        return getVariant(experimentId: experimentId) == variantId
    }

    /// Get a specific config value from the assigned variant's payload.
    func getExperimentConfig(experimentId: String, key: String) -> Any? {
        guard let config = resolveConfig(experimentId: experimentId) else { return nil }

        let identity = identityManager.currentIdentity
        let userId = identity.userId ?? identity.anonId

        guard let variantId = ExperimentBucketer.assignVariant(
            experimentId: experimentId,
            userId: userId,
            salt: config.salt,
            variants: config.variants
        ) else {
            return nil
        }

        // Track exposure (once per session)
        trackExposure(experimentId: experimentId, variant: variantId)

        // Find variant and return config value
        guard let variant = config.variants.first(where: { $0.id == variantId }),
              let payload = variant.payload else {
            return nil
        }

        return payload[key]?.value
    }

    /// Get all active experiment exposures as (experimentId, variant) tuples.
    func getExposures() -> [(experimentId: String, variant: String)] {
        queue.sync {
            exposedExperiments.map { (experimentId: $0.key, variant: $0.value) }
        }
    }

    /// Reset exposure tracking (called on identity reset or new session).
    func resetExposures() {
        queue.sync { exposedExperiments.removeAll() }
    }

    // MARK: - Private

    private func resolveConfig(experimentId: String) -> ExperimentConfig? {
        guard let config = remoteConfigManager.getExperimentConfig(id: experimentId) else {
            Log.debug("Experiment '\(experimentId)' not found in config")
            return nil
        }

        guard config.status == "running" else {
            Log.debug("Experiment '\(experimentId)' is not running (status: \(config.status))")
            return nil
        }

        guard config.platforms.contains("ios") else {
            Log.debug("Experiment '\(experimentId)' does not target iOS")
            return nil
        }

        return config
    }

    private func trackExposure(experimentId: String, variant: String) {
        queue.sync {
            if exposedExperiments[experimentId] == nil {
                exposedExperiments[experimentId] = variant
                eventTracker.track(event: "experiment_exposure", properties: [
                    "experiment_id": experimentId,
                    "variant": variant,
                    "source": "sdk",
                ])
            }
        }
    }
}

// MARK: - MurmurHash3 (kept for backward compatibility; delegates to ExperimentBucketer)

enum MurmurHash3 {
    static func hash32(_ key: String, seed: UInt32 = 0) -> UInt32 {
        ExperimentBucketer.hash32(key, seed: seed)
    }
}
