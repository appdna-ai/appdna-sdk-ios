import XCTest
@testable import AppDNASDK

final class MurmurHash3Tests: XCTestCase {

    // MARK: - Known test vectors
    // Reference: https://github.com/aappleby/smhasher

    func testEmptyString() {
        let hash = MurmurHash3.hash32("", seed: 0)
        XCTAssertEqual(hash, 0)
    }

    func testEmptyStringWithSeed() {
        let hash = MurmurHash3.hash32("", seed: 1)
        XCTAssertEqual(hash, 0x514E28B7)
    }

    func testKnownVector1() {
        // MurmurHash3_x86_32("Hello", 0) = 316307400 (0x12da77c8)
        let hash = MurmurHash3.hash32("Hello", seed: 0)
        XCTAssertEqual(hash, 316307400)
    }

    func testDeterminism() {
        // Same input always produces the same output
        let input = "user_123.exp_001.salt_abc"
        let hash1 = MurmurHash3.hash32(input)
        let hash2 = MurmurHash3.hash32(input)
        let hash3 = MurmurHash3.hash32(input)
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, hash3)
    }

    func testDeterminismOver100Runs() {
        let input = "test_user.experiment_id.salt"
        let expected = MurmurHash3.hash32(input)
        for _ in 0..<100 {
            XCTAssertEqual(MurmurHash3.hash32(input), expected)
        }
    }

    func testDifferentInputsProduceDifferentHashes() {
        let hash1 = MurmurHash3.hash32("input_a")
        let hash2 = MurmurHash3.hash32("input_b")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testLongString() {
        let longString = String(repeating: "abcdefghij", count: 1000) // 10,000 chars
        let hash = MurmurHash3.hash32(longString)
        XCTAssertNotEqual(hash, 0)
        // Verify determinism
        XCTAssertEqual(hash, MurmurHash3.hash32(longString))
    }

    func testUnicode() {
        let hash1 = MurmurHash3.hash32("日本語テスト")
        let hash2 = MurmurHash3.hash32("日本語テスト")
        XCTAssertEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, 0)
    }

    func testEmojiString() {
        let hash = MurmurHash3.hash32("🎉🚀💡")
        XCTAssertNotEqual(hash, 0)
        XCTAssertEqual(hash, MurmurHash3.hash32("🎉🚀💡"))
    }

    func testSingleCharStrings() {
        // Each single char should produce a different hash
        let hashes = Set((0..<26).map { i in
            MurmurHash3.hash32(String(Character(UnicodeScalar(65 + i)!)))
        })
        // All 26 should be unique (extremely unlikely to collide)
        XCTAssertEqual(hashes.count, 26)
    }

    func testSeedAffectsOutput() {
        let input = "test_input"
        let hash0 = MurmurHash3.hash32(input, seed: 0)
        let hash1 = MurmurHash3.hash32(input, seed: 42)
        XCTAssertNotEqual(hash0, hash1)
    }

    // MARK: - Byte alignment edge cases

    func testOneByteString() {
        XCTAssertEqual(MurmurHash3.hash32("a"), 1009084850)
    }

    func testTwoByteString() {
        XCTAssertEqual(MurmurHash3.hash32("ab"), 2613040991)
    }

    func testThreeByteString() {
        XCTAssertEqual(MurmurHash3.hash32("abc"), 3017643002)
    }

    func testFourByteString() {
        XCTAssertEqual(MurmurHash3.hash32("abcd"), 1139631978)
    }

    func testFiveByteString() {
        XCTAssertEqual(MurmurHash3.hash32("abcde"), 3902511862)
    }
}
