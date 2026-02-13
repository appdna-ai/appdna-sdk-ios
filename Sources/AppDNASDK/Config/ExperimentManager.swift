import Foundation

/// Manages experiment variant assignment via deterministic MurmurHash3 bucketing.
/// Tracks exposure events once per session per experiment.
final class ExperimentManager {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.experiments")
    private let remoteConfigManager: RemoteConfigManager
    private let identityManager: IdentityManager
    private let eventTracker: EventTracker

    /// Set of experiment IDs for which exposure has been tracked this session.
    private var exposedExperiments: Set<String> = []

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
        guard let config = remoteConfigManager.getExperimentConfig(id: experimentId) else {
            Log.debug("Experiment '\(experimentId)' not found in config")
            return nil
        }

        // Check experiment is running
        guard config.status == "running" else {
            Log.debug("Experiment '\(experimentId)' is not running (status: \(config.status))")
            return nil
        }

        // Check platform targeting
        guard config.platforms.contains("ios") else {
            Log.debug("Experiment '\(experimentId)' does not target iOS")
            return nil
        }

        let identity = identityManager.currentIdentity
        let userId = identity.userId ?? identity.anonId

        // Deterministic bucketing
        guard let variant = assignVariant(
            userId: userId,
            experimentId: experimentId,
            salt: config.salt,
            variants: config.variants
        ) else {
            return nil
        }

        // Track exposure (once per session)
        queue.sync {
            if !exposedExperiments.contains(experimentId) {
                exposedExperiments.insert(experimentId)
                eventTracker.track(event: "experiment_exposure", properties: [
                    "experiment_id": experimentId,
                    "variant": variant,
                    "source": "sdk",
                ])
            }
        }

        return variant
    }

    /// Reset exposure tracking (called on identity reset).
    func resetExposures() {
        queue.sync { exposedExperiments.removeAll() }
    }

    // MARK: - Deterministic bucketing

    private func assignVariant(
        userId: String,
        experimentId: String,
        salt: String,
        variants: [ExperimentVariant]
    ) -> String? {
        guard !variants.isEmpty else { return nil }

        let hashInput = "\(userId).\(experimentId).\(salt)"
        let hash = MurmurHash3.hash32(hashInput)
        let bucket = Double(hash % 10000) / 10000.0 // 0.0000 - 0.9999

        var cumulative: Double = 0
        for variant in variants {
            cumulative += variant.weight
            if bucket < cumulative {
                return variant.id
            }
        }

        return variants.last?.id
    }
}

// MARK: - MurmurHash3 (32-bit, inline implementation)

enum MurmurHash3 {
    /// Standard MurmurHash3 32-bit implementation.
    static func hash32(_ key: String, seed: UInt32 = 0) -> UInt32 {
        let data = Array(key.utf8)
        let len = data.count
        let nblocks = len / 4

        var h1: UInt32 = seed

        let c1: UInt32 = 0xcc9e2d51
        let c2: UInt32 = 0x1b873593

        // Body — process 4-byte blocks
        for i in 0..<nblocks {
            let offset = i * 4
            var k1: UInt32 = UInt32(data[offset])
            k1 |= UInt32(data[offset + 1]) << 8
            k1 |= UInt32(data[offset + 2]) << 16
            k1 |= UInt32(data[offset + 3]) << 24

            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2

            h1 ^= k1
            h1 = (h1 << 13) | (h1 >> 19)
            h1 = h1 &* 5 &+ 0xe6546b64
        }

        // Tail — process remaining bytes
        let tail = nblocks * 4
        var k1: UInt32 = 0

        switch len & 3 {
        case 3:
            k1 ^= UInt32(data[tail + 2]) << 16
            fallthrough
        case 2:
            k1 ^= UInt32(data[tail + 1]) << 8
            fallthrough
        case 1:
            k1 ^= UInt32(data[tail])
            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2
            h1 ^= k1
        default:
            break
        }

        // Finalization
        h1 ^= UInt32(len)
        h1 ^= h1 >> 16
        h1 = h1 &* 0x85ebca6b
        h1 ^= h1 >> 13
        h1 = h1 &* 0xc2b2ae35
        h1 ^= h1 >> 16

        return h1
    }
}
