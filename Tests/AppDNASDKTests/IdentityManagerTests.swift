import XCTest
@testable import AppDNASDK

final class IdentityManagerTests: XCTestCase {

    private var keychainStore: KeychainStore!
    private var manager: IdentityManager!

    override func setUp() {
        super.setUp()
        // Use a test-specific keychain service to avoid polluting real data
        keychainStore = KeychainStore(service: "ai.appdna.sdk.test.\(UUID().uuidString)")
        manager = IdentityManager(keychainStore: keychainStore)
    }

    // MARK: - Anonymous ID

    func testAnonIdGeneratedOnFirstLaunch() {
        let identity = manager.currentIdentity
        XCTAssertFalse(identity.anonId.isEmpty)
    }

    func testAnonIdIsValidUUID() {
        let identity = manager.currentIdentity
        XCTAssertNotNil(UUID(uuidString: identity.anonId))
    }

    func testAnonIdPersistedToKeychain() {
        let anonId = manager.currentIdentity.anonId
        // Create new manager with same keychain — should load same ID
        let manager2 = IdentityManager(keychainStore: keychainStore)
        XCTAssertEqual(manager2.currentIdentity.anonId, anonId)
    }

    func testAnonIdStableAcrossMultipleAccesses() {
        let id1 = manager.currentIdentity.anonId
        let id2 = manager.currentIdentity.anonId
        let id3 = manager.currentIdentity.anonId
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id2, id3)
    }

    // MARK: - Identify

    func testIdentifySetsUserId() {
        manager.identify(userId: "user_123")
        XCTAssertEqual(manager.currentIdentity.userId, "user_123")
    }

    func testIdentifySetsTraits() {
        manager.identify(userId: "user_123", traits: ["plan": "pro", "age": 25])
        let traits = manager.currentIdentity.traits
        XCTAssertEqual(traits?["plan"] as? String, "pro")
        XCTAssertEqual(traits?["age"] as? Int, 25)
    }

    func testIdentifyPersistsToKeychain() {
        manager.identify(userId: "user_456", traits: ["name": "Test"])
        let manager2 = IdentityManager(keychainStore: keychainStore)
        XCTAssertEqual(manager2.currentIdentity.userId, "user_456")
    }

    func testIdentifyOverwritesPrevious() {
        manager.identify(userId: "user_1")
        manager.identify(userId: "user_2")
        XCTAssertEqual(manager.currentIdentity.userId, "user_2")
    }

    // MARK: - Reset

    func testResetClearsUserId() {
        manager.identify(userId: "user_123")
        manager.reset()
        XCTAssertNil(manager.currentIdentity.userId)
    }

    func testResetClearsTraits() {
        manager.identify(userId: "user_123", traits: ["plan": "pro"])
        manager.reset()
        XCTAssertNil(manager.currentIdentity.traits)
    }

    func testResetKeepsAnonId() {
        let anonId = manager.currentIdentity.anonId
        manager.identify(userId: "user_123")
        manager.reset()
        XCTAssertEqual(manager.currentIdentity.anonId, anonId)
    }

    func testResetPersistsToKeychain() {
        manager.identify(userId: "user_123")
        manager.reset()
        let manager2 = IdentityManager(keychainStore: keychainStore)
        XCTAssertNil(manager2.currentIdentity.userId)
        XCTAssertFalse(manager2.currentIdentity.anonId.isEmpty)
    }

    // MARK: - Thread safety

    func testConcurrentIdentifyCalls() {
        let expectation = self.expectation(description: "concurrent")
        expectation.expectedFulfillmentCount = 100

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            queue.async {
                self.manager.identify(userId: "user_\(i)")
                _ = self.manager.currentIdentity
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)
        // Should not crash — that's the test
        let identity = manager.currentIdentity
        XCTAssertFalse(identity.anonId.isEmpty)
    }

    func testConcurrentResetCalls() {
        let expectation = self.expectation(description: "concurrent reset")
        expectation.expectedFulfillmentCount = 50

        let queue = DispatchQueue(label: "test.concurrent.reset", attributes: .concurrent)

        for i in 0..<50 {
            queue.async {
                if i % 2 == 0 {
                    self.manager.identify(userId: "user_\(i)")
                } else {
                    self.manager.reset()
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)
        // Should not crash
        XCTAssertFalse(manager.currentIdentity.anonId.isEmpty)
    }
}
