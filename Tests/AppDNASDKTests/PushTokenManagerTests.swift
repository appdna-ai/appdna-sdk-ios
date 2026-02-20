import XCTest
import CommonCrypto
@testable import AppDNASDK

final class PushTokenManagerTests: XCTestCase {

    // MARK: - SHA256 token hashing format

    func testTokenHashIsCorrectLength() {
        let tokenBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]
        let hash = sha256Hex(Data(tokenBytes))
        XCTAssertEqual(hash.count, 64) // SHA256 = 64 hex chars
    }

    func testTokenHashIsDeterministic() {
        let token = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(sha256Hex(token), sha256Hex(token))
    }

    func testDifferentTokensDifferentHashes() {
        let token1 = Data([0x01, 0x02, 0x03])
        let token2 = Data([0x04, 0x05, 0x06])
        XCTAssertNotEqual(sha256Hex(token1), sha256Hex(token2))
    }

    func testTokenHashIsLowercaseHex() {
        let hash = sha256Hex(Data([0xFF]))
        let validChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hash.unicodeScalars.allSatisfy { validChars.contains($0) })
    }

    // MARK: - Helper

    private func sha256Hex(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
