import XCTest
@testable import AppDNASDK

/// Cross-platform MurmurHash3 test vectors.
/// These EXACT values must match the Android Kotlin implementation.
/// Reference: verified against mmh3 C library.
final class CrossPlatformBucketingTests: XCTestCase {

    // MARK: - Exact hash value vectors (seed = 0)

    func testEmptyStringHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("", seed: 0), 0)
    }

    func testEmptyStringWithSeed1() {
        XCTAssertEqual(ExperimentBucketer.hash32("", seed: 1), 0x514E28B7)
    }

    func testHelloHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("Hello", seed: 0), 316307400)
    }

    func testSingleCharHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("a", seed: 0), 1009084850)
    }

    func testTwoCharHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("ab", seed: 0), 2613040991)
    }

    func testThreeCharHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("abc", seed: 0), 3017643002)
    }

    func testFourCharHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("abcd", seed: 0), 1139631978)
    }

    func testFiveCharHash() {
        XCTAssertEqual(ExperimentBucketer.hash32("abcde", seed: 0), 3902511862)
    }

    // MARK: - Experiment-style input vectors

    func testExperimentInputPaywall() {
        XCTAssertEqual(
            ExperimentBucketer.hash32("exp_paywall_v3.a8f3c9d2.user_12345", seed: 0),
            3214585791
        )
    }

    func testExperimentInputOnboard() {
        XCTAssertEqual(
            ExperimentBucketer.hash32("exp_onboard.salt_x.user_99999", seed: 0),
            1911481070
        )
    }

    func testExperimentInputTest() {
        XCTAssertEqual(
            ExperimentBucketer.hash32("exp_test.salt_abc.user_1", seed: 0),
            3276853400
        )
    }

    // MARK: - Unicode / multi-byte vectors

    func testJapaneseHash() {
        XCTAssertEqual(
            ExperimentBucketer.hash32("日本語テスト", seed: 0),
            3057250137
        )
    }

    func testEmojiHash() {
        XCTAssertEqual(
            ExperimentBucketer.hash32("🎉🚀💡", seed: 0),
            665358373
        )
    }

    // MARK: - Seed variation vectors

    func testSeedVariation() {
        XCTAssertEqual(ExperimentBucketer.hash32("test_input", seed: 0), 3222140578)
        XCTAssertEqual(ExperimentBucketer.hash32("test_input", seed: 42), 1837767272)
    }

    // MARK: - Bucket assignment cross-platform consistency

    func testBucketAssignmentPaywallExperiment() {
        // hash = 3214585791, bucket = 3214585791 % 10000 = 5791
        // With 50/50 split (control=0.5, variant_b=0.5):
        //   cumulative after control = 5000, 5791 >= 5000 → skip
        //   cumulative after variant_b = 10000, 5791 < 10000 → variant_b
        let hash = ExperimentBucketer.hash32("exp_paywall_v3.a8f3c9d2.user_12345", seed: 0)
        let bucket = hash % 10000
        XCTAssertEqual(bucket, 5791)

        let result = ExperimentBucketer.assignVariant(
            experimentId: "exp_paywall_v3",
            userId: "user_12345",
            salt: "a8f3c9d2",
            variants: [
                ExperimentVariant(id: "control", weight: 0.5, payload: nil),
                ExperimentVariant(id: "variant_b", weight: 0.5, payload: nil),
            ]
        )
        XCTAssertEqual(result, "variant_b")
    }

    func testBucketAssignmentOnboardExperiment() {
        // hash = 1911481070, bucket = 1911481070 % 10000 = 1070
        // With 50/50: cumulative after control = 5000, 1070 < 5000 → control
        let hash = ExperimentBucketer.hash32("exp_onboard.salt_x.user_99999", seed: 0)
        let bucket = hash % 10000
        XCTAssertEqual(bucket, 1070)

        let result = ExperimentBucketer.assignVariant(
            experimentId: "exp_onboard",
            userId: "user_99999",
            salt: "salt_x",
            variants: [
                ExperimentVariant(id: "control", weight: 0.5, payload: nil),
                ExperimentVariant(id: "treatment", weight: 0.5, payload: nil),
            ]
        )
        XCTAssertEqual(result, "control")
    }

    func testBucketAssignment7030Split() {
        // hash for "exp_test.salt_abc.user_1" = 3276853400, bucket = 3400
        // 70/30: cumulative after A = 7000, 3400 < 7000 → variant A
        let hash = ExperimentBucketer.hash32("exp_test.salt_abc.user_1", seed: 0)
        let bucket = hash % 10000
        XCTAssertEqual(bucket, 3400)

        let result = ExperimentBucketer.assignVariant(
            experimentId: "exp_test",
            userId: "user_1",
            salt: "salt_abc",
            variants: [
                ExperimentVariant(id: "variant_a", weight: 0.7, payload: nil),
                ExperimentVariant(id: "variant_b", weight: 0.3, payload: nil),
            ]
        )
        XCTAssertEqual(result, "variant_a")
    }

    // MARK: - Backward compatibility (MurmurHash3 alias)

    func testMurmurHash3AliasMatchesBucketer() {
        let inputs = ["Hello", "test_input", "exp_paywall_v3.a8f3c9d2.user_12345"]
        for input in inputs {
            XCTAssertEqual(
                MurmurHash3.hash32(input, seed: 0),
                ExperimentBucketer.hash32(input, seed: 0)
            )
        }
    }
}
