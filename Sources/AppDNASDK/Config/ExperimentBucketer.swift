import Foundation

/// Pure MurmurHash3 32-bit implementation for deterministic experiment bucketing.
/// This must produce IDENTICAL results to the Android Kotlin implementation.
public enum ExperimentBucketer {

    /// Standard MurmurHash3 32-bit hash.
    /// - Parameters:
    ///   - key: The string to hash
    ///   - seed: Hash seed (default 0)
    /// - Returns: 32-bit hash value
    public static func hash32(_ key: String, seed: UInt32 = 0) -> UInt32 {
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

    /// Assign a variant based on deterministic bucketing.
    /// - Parameters:
    ///   - experimentId: The experiment identifier
    ///   - userId: The user identifier
    ///   - salt: Experiment-specific salt to prevent cross-experiment correlation
    ///   - variants: Array of variants with weights (0.0-1.0, summing to 1.0)
    /// - Returns: The assigned variant ID, or nil if variants are empty
    public static func assignVariant(
        experimentId: String,
        userId: String,
        salt: String,
        variants: [ExperimentVariant]
    ) -> String? {
        guard !variants.isEmpty else { return nil }

        let hashInput = "\(experimentId).\(salt).\(userId)"
        let hash = hash32(hashInput)
        let bucket = hash % 10000 // 0-9999

        var cumulative: UInt32 = 0
        for variant in variants {
            cumulative += UInt32(variant.weight * 10000)
            if bucket < cumulative {
                return variant.id
            }
        }

        return variants.last?.id
    }
}
