import XCTest
@testable import AppDNASDK

final class ExperimentManagerTests: XCTestCase {

    // MARK: - Deterministic bucketing

    func testDeterministicBucketing() {
        // Same input → same output, run 100 times
        let input = "user_abc.experiment_1.salt_xyz"
        let expected = MurmurHash3.hash32(input)

        for _ in 0..<100 {
            XCTAssertEqual(MurmurHash3.hash32(input), expected)
        }
    }

    func testDifferentUsersDifferentBuckets() {
        let hash1 = MurmurHash3.hash32("user_1.exp_1.salt")
        let hash2 = MurmurHash3.hash32("user_2.exp_1.salt")
        // Different users should (almost certainly) get different hashes
        XCTAssertNotEqual(hash1, hash2)
    }

    func testBucketDistribution5050() {
        // Simulate 10,000 users in a 50/50 experiment
        var variantACounts = 0
        var variantBCounts = 0

        for i in 0..<10_000 {
            let hashInput = "user_\(i).test_experiment.test_salt"
            let hash = MurmurHash3.hash32(hashInput)
            let bucket = Double(hash % 10000) / 10000.0

            if bucket < 0.5 {
                variantACounts += 1
            } else {
                variantBCounts += 1
            }
        }

        let total = Double(variantACounts + variantBCounts)
        let ratioA = Double(variantACounts) / total
        let ratioB = Double(variantBCounts) / total

        // Each variant should be within 48-52% range
        XCTAssertGreaterThan(ratioA, 0.48, "Variant A ratio \(ratioA) is too low")
        XCTAssertLessThan(ratioA, 0.52, "Variant A ratio \(ratioA) is too high")
        XCTAssertGreaterThan(ratioB, 0.48, "Variant B ratio \(ratioB) is too low")
        XCTAssertLessThan(ratioB, 0.52, "Variant B ratio \(ratioB) is too high")
    }

    func testBucketDistribution7030() {
        // 70/30 split
        var variantACounts = 0
        var variantBCounts = 0

        for i in 0..<10_000 {
            let hashInput = "user_\(i).exp_7030.salt_abc"
            let hash = MurmurHash3.hash32(hashInput)
            let bucket = Double(hash % 10000) / 10000.0

            if bucket < 0.7 {
                variantACounts += 1
            } else {
                variantBCounts += 1
            }
        }

        let total = Double(variantACounts + variantBCounts)
        let ratioA = Double(variantACounts) / total

        // Should be approximately 70%
        XCTAssertGreaterThan(ratioA, 0.68, "70/30 split: variant A ratio \(ratioA) is too low")
        XCTAssertLessThan(ratioA, 0.72, "70/30 split: variant A ratio \(ratioA) is too high")
    }

    // MARK: - Variant assignment logic

    func testAssignVariantWithTwoVariants() {
        // Create a test case where we manually bucket
        let variants = [
            ExperimentVariant(id: "control", weight: 0.5, payload: nil),
            ExperimentVariant(id: "treatment", weight: 0.5, payload: nil),
        ]

        // Test assignment for a specific user
        var controlCount = 0
        var treatmentCount = 0

        for i in 0..<1000 {
            let hashInput = "user_\(i).exp.salt"
            let hash = MurmurHash3.hash32(hashInput)
            let bucket = Double(hash % 10000) / 10000.0

            var cumulative: Double = 0
            for variant in variants {
                cumulative += variant.weight
                if bucket < cumulative {
                    if variant.id == "control" {
                        controlCount += 1
                    } else {
                        treatmentCount += 1
                    }
                    break
                }
            }
        }

        // Both should have roughly 500 users
        XCTAssertGreaterThan(controlCount, 400)
        XCTAssertGreaterThan(treatmentCount, 400)
    }

    func testAssignVariantWithThreeVariants() {
        let variants = [
            ExperimentVariant(id: "control", weight: 0.34, payload: nil),
            ExperimentVariant(id: "variant_a", weight: 0.33, payload: nil),
            ExperimentVariant(id: "variant_b", weight: 0.33, payload: nil),
        ]

        var counts: [String: Int] = ["control": 0, "variant_a": 0, "variant_b": 0]

        for i in 0..<10_000 {
            let hashInput = "user_\(i).three_variant_exp.salt"
            let hash = MurmurHash3.hash32(hashInput)
            let bucket = Double(hash % 10000) / 10000.0

            var cumulative: Double = 0
            for variant in variants {
                cumulative += variant.weight
                if bucket < cumulative {
                    counts[variant.id, default: 0] += 1
                    break
                }
            }
        }

        // Each should be roughly 33%
        for (id, count) in counts {
            let ratio = Double(count) / 10000.0
            XCTAssertGreaterThan(ratio, 0.30, "\(id) ratio \(ratio) is too low")
            XCTAssertLessThan(ratio, 0.37, "\(id) ratio \(ratio) is too high")
        }
    }

    // MARK: - Stability

    func testSameUserAlwaysSameVariant() {
        let userId = "stable_user_123"
        let experimentId = "stable_exp"
        let salt = "stable_salt"

        let hashInput = "\(userId).\(experimentId).\(salt)"
        let hash = MurmurHash3.hash32(hashInput)
        let bucket = Double(hash % 10000) / 10000.0

        // Run 100 times — should always get same bucket
        for _ in 0..<100 {
            let h = MurmurHash3.hash32(hashInput)
            let b = Double(h % 10000) / 10000.0
            XCTAssertEqual(b, bucket)
        }
    }
}
