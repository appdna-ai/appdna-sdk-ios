import XCTest
@testable import AppDNASDK

/// The pending-event log is plaintext NDJSON holding whatever properties and traits
/// the host chose to send. Application Support is backed up by default, so without
/// `isExcludedFromBackup` the queue is copied into the user's iCloud backup.
final class BackupExclusionTests: XCTestCase {

    /// The directory `EventStore` writes into.
    private var sdkDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ai.appdna.sdk", isDirectory: true)
    }

    /// The exclusion flag is a persistent filesystem attribute. Once any earlier
    /// test (or run) sets it on the shared SDK directory, it stays set — so a test
    /// that merely reads it back passes even when `EventStore` no longer sets it.
    /// Clear it first, or the assertion proves nothing.
    private func clearExclusionFlag() throws {
        var dir = sdkDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try dir.setResourceValues(values)

        let check = try sdkDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(check.isExcludedFromBackup, false, "precondition: flag must start cleared")
    }

    func testEventStoreDirectoryIsExcludedFromBackup() throws {
        try clearExclusionFlag()

        // Constructing an EventStore creates the directory and sets the flag.
        _ = EventStore(fileName: "backup_exclusion_probe.json")

        let values = try sdkDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true,
                       "SDK storage must not be copied into iCloud backup")
    }

    func testExclusionIsIdempotent() throws {
        try clearExclusionFlag()

        // Called on every EventStore init — must not throw or flip the flag off.
        _ = EventStore(fileName: "backup_exclusion_probe_a.json")
        _ = EventStore(fileName: "backup_exclusion_probe_b.json")

        let values = try sdkDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testExcludeFromBackupOnMissingPathDoesNotThrow() {
        // First-run races and unsupported volumes must never block event storage.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("appdna-does-not-exist-\(UUID().uuidString)")
        EventStore.excludeFromBackup(missing) // must not trap
    }
}
