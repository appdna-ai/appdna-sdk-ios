import XCTest
@testable import AppDNASDK

/// 🔴 `shutdown()` FOLLOWED BY `configure()` ON THE SAME TICK LEFT THE SDK DEAD FOR THE PROCESS.
///
/// `configure()` checks `isConfigured` synchronously under `initLock` and returns early if it is true.
/// `shutdown()` used to clear that flag ONLY inside its async teardown block. So the ordinary
/// sign-out→sign-in / React-Native-reload sequence —
///
///     AppDNA.shutdown()
///     AppDNA.configure(apiKey: …)   // same tick
///
/// ran `configure()` while the teardown was merely SCHEDULED: `isConfigured` was still true, the
/// configure was ignored with a log line, and then the teardown nilled everything. No event pipeline,
/// no billing, no managers, until the process restarted — and no `shutdown()` completion callback to
/// wait on, so a host could not even work around it.
///
/// This drives the exact back-to-back sequence a host issues and asserts the SDK comes back UP.
final class ShutdownReconfigureRaceTests: XCTestCase {

    override func tearDown() {
        AppDNA.resetInitStateForTesting()
        AppDNA.shutdown()
        waitUntil("torn down") { AppDNA.subsystemsUp()["events"] == false }
        super.tearDown()
    }

    private func waitUntil(
        _ what: String, timeout: TimeInterval = 30, _ cond: @escaping () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() >= deadline { return XCTFail("timed out: \(what)", file: file, line: line) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testShutdownThenConfigureOnTheSameTickLeavesTheSDKConfigured() {
        // First configure + reach ready.
        AppDNA.configure(apiKey: "adn_test_placeholder", environment: .sandbox)
        let up1 = expectation(description: "first configure ready")
        AppDNA.onReady { up1.fulfill() }
        wait(for: [up1], timeout: 30)

        // The sequence under test: shutdown() IMMEDIATELY followed by configure(), no thread hop, no
        // wait between them — exactly what a sign-out→sign-in handler does.
        AppDNA.shutdown()
        AppDNA.configure(apiKey: "adn_test_placeholder", environment: .sandbox)

        // If the reconfigure was swallowed by the still-true `isConfigured`, `onReady` never fires again
        // and the SDK is dead. It must come back up.
        let up2 = expectation(description: "reconfigure after shutdown reached ready")
        AppDNA.onReady { up2.fulfill() }
        wait(for: [up2], timeout: 30)

        XCTAssertEqual(
            AppDNA.subsystemsUp()["events"], true,
            "shutdown() immediately before configure() swallowed the reconfigure — the SDK is dead"
        )
    }
}
