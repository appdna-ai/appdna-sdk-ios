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
            salt: config.salt ?? experimentId,
            variants: config.variants ?? []
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
            salt: config.salt ?? experimentId,
            variants: config.variants ?? []
        ) else {
            return nil
        }

        // Track exposure (once per session)
        trackExposure(experimentId: experimentId, variant: variantId)

        // Find variant and return config value
        guard let variant = (config.variants ?? []).first(where: { $0.id == variantId }),
              let payload = variant.payload else {
            return nil
        }

        return payload[key]?.value
    }

    // MARK: - SPEC-036-F §1.2 — experiment-aware surface presentation

    /// The outcome of resolving whether a running experiment governs how a
    /// given surface entity should be presented.
    enum SurfaceResolution {
        /// No running experiment targets this surface+entity, the user wasn't
        /// bucketed, or the SDK fell to the control bucket → render the live
        /// active entity through the normal (index-backed) path.
        case renderActive
        /// The user is bucketed into the treatment variant → render the inlined
        /// `payload` config instead of the active entity. The dictionary is the
        /// raw Firestore-shaped config map (same shape `parsePaywalls` etc.
        /// consume), ready to run through `sanitizedJSONData`.
        case renderTreatment(experimentId: String, variantId: String, payload: [String: Any])
    }

    /// SPEC-036-F §1.2 — decide whether a `running` experiment governs the
    /// presentation of `entityId` for the given surface `type`. Matches an
    /// experiment whose served `type` == `surfaceType` AND whose control
    /// variant's `config_ref` == `entityId` (the entity the host is about to
    /// present). On a match the user is bucketed via the SAME
    /// `ExperimentBucketer.assignVariant` path (+ exposure tracked):
    ///   - control bucket / no payload → `.renderActive`
    ///   - treatment bucket with payload → `.renderTreatment(...)`
    /// Cohort isolation (§1.3): the treatment config lives ONLY in the
    /// experiment doc payload, so a non-bucketed / control / old-SDK user can
    /// never resolve to it — they always fall to `.renderActive`.
    func resolveSurfacePresentation(surfaceType: String, entityId: String) -> SurfaceResolution {
        let allExperiments = remoteConfigManager.getAllExperiments()

        for (experimentId, config) in allExperiments {
            // Only `running` experiments serve, and only on the requested
            // platform (`resolveConfig` enforces both — reuse it).
            guard config.status == "running" else { continue }
            guard config.type == surfaceType else { continue }
            guard (config.platforms ?? []).contains("ios") else { continue }

            // The control variant's config_ref names the live active entity.
            let variants = config.variants ?? []
            guard variants.contains(where: { ($0.is_control ?? false) && $0.config_ref == entityId }) else {
                continue
            }

            // Bucket the user deterministically (same path as getVariant).
            let identity = identityManager.currentIdentity
            let userId = identity.userId ?? identity.anonId
            guard let variantId = ExperimentBucketer.assignVariant(
                experimentId: experimentId,
                userId: userId,
                salt: config.salt ?? experimentId,
                variants: variants
            ) else {
                continue
            }

            // Track exposure once per session, regardless of bucket — the user
            // WAS exposed to the experiment by virtue of seeing this surface.
            trackExposure(experimentId: experimentId, variant: variantId)

            guard let variant = variants.first(where: { $0.id == variantId }) else {
                return .renderActive
            }

            // Control bucket → render the live active entity. Treatment WITHOUT
            // a payload (e.g. an old/over-limit served doc that dropped it) →
            // safe fallback to active. Only a treatment WITH a payload renders
            // the variant config.
            if (variant.is_control ?? false) {
                return .renderActive
            }
            guard let payloadCodable = variant.payload else {
                return .renderActive
            }
            // Unwrap [String: AnyCodable] → [String: Any] for the typed-config
            // decode pipeline (sanitizedJSONData) the surface managers run.
            let payload = payloadCodable.mapValues { $0.value }
            return .renderTreatment(experimentId: experimentId, variantId: variantId, payload: payload)
        }

        return .renderActive
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
            Log.debug("Experiment '\(experimentId)' is not running (status: \(config.status ?? "unknown"))")
            return nil
        }

        guard (config.platforms ?? []).contains("ios") else {
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
