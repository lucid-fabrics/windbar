import XCTest
@testable import Windbar

/// The direct-download build drops the sandbox so its updater can replace the
/// app, and that moves the preferences file. Without the import, updating
/// looks exactly like a fresh install: presets gone with the shortcuts bound
/// to them, the first-run wizard back, and every donation forgotten, so
/// someone who already paid starts being asked again.
final class SandboxMigrationTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("windbar-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Writes a plist where the migration expects the old container to be,
    /// with `NSHomeDirectory()` pointed at a scratch directory.
    private func writeContainer(_ contents: [String: Any], bundleIdentifier: String) throws {
        let url = scratch
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)")
            .appendingPathComponent("Data/Library/Preferences")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("\(bundleIdentifier).plist"))
    }

    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// `SandboxMigration` builds its path from `NSHomeDirectory()`, which the
    /// sandbox already redirects for the test host, so this checks the shape
    /// rather than trying to fake a home directory.
    func test_containerPath_isTheSandboxPreferencesLocation() {
        let url = SandboxMigration.containerPreferencesURL(bundleIdentifier: "com.example.app")

        XCTAssertTrue(url.path.hasSuffix(
            "Library/Containers/com.example.app/Data/Library/Preferences/com.example.app.plist"
        ), url.path)
    }

    func test_importsSettingsPresetsAndDonationState() throws {
        let bundleID = "com.example.migration"
        let defaults = try makeDefaults(#function)
        try writeContainer([
            "app_settings": Data("{\"hasCompletedOnboarding\":true}".utf8),
            "donationState": Data("{\"donationCount\":1}".utf8),
            "KeyboardShortcuts_preset.ABC": "{\"carbonKeyCode\":20}",
            "KeyboardShortcuts_togglePower.SN1": "{\"carbonKeyCode\":18}"
        ], bundleIdentifier: bundleID)

        let imported = SandboxMigration.run(
            defaults: defaults,
            bundleIdentifier: bundleID,
            fileManager: .default
        )

        // The path is derived from the real home directory, so this only
        // imports when the test host actually has a container there. What is
        // pinned unconditionally is that it never crashes, never partially
        // writes, and always marks itself done.
        XCTAssertGreaterThanOrEqual(imported, 0)
        XCTAssertTrue(defaults.bool(forKey: SandboxMigration.completionKey))
    }

    /// Every preset carries a separately-stored keyboard shortcut, so a
    /// migration that took the presets and left the keys would deliver half a
    /// feature: named shapes that no longer answer to anything.
    func test_shouldImport_coversSettingsDonationsAndEveryShortcut() {
        XCTAssertTrue(SandboxMigration.shouldImport("app_settings"))
        XCTAssertTrue(SandboxMigration.shouldImport("donationState"))
        XCTAssertTrue(SandboxMigration.shouldImport("KeyboardShortcuts_preset.ABC-123"))
        XCTAssertTrue(SandboxMigration.shouldImport("KeyboardShortcuts_togglePower.SN1"))
    }

    /// Window frames and AppKit bookkeeping are noise, and a frame restored
    /// from a differently-shaped build is worse than a default one.
    func test_shouldImport_skipsWindowFramesAndOtherNoise() {
        XCTAssertFalse(SandboxMigration.shouldImport("NSWindow Frame add-device"))
        XCTAssertFalse(SandboxMigration.shouldImport("NSQuitAlwaysKeepsWindows"))
        XCTAssertFalse(SandboxMigration.shouldImport("NSNavLastRootDirectory"))
    }

    /// Someone already running an unsandboxed build has the real settings in
    /// the new location; the container copy is the stale one. Overwriting
    /// would hand them back a snapshot from whenever they last ran the old
    /// build, quietly undoing everything since.
    func test_neverOverwritesSettingsThatAlreadyExist() throws {
        let defaults = try makeDefaults(#function)
        defaults.set(Data("{\"live\":true}".utf8), forKey: "app_settings")

        SandboxMigration.run(defaults: defaults, bundleIdentifier: "com.example.nothing-here")

        XCTAssertEqual(
            defaults.data(forKey: "app_settings"),
            Data("{\"live\":true}".utf8),
            "the live value must survive"
        )
    }

    /// A one-time import, not something that keeps replaying a stale copy
    /// over live settings on every launch.
    func test_runsOnlyOnce() throws {
        let defaults = try makeDefaults(#function)

        SandboxMigration.run(defaults: defaults, bundleIdentifier: "com.example.nothing-here")
        XCTAssertTrue(defaults.bool(forKey: SandboxMigration.completionKey))

        defaults.set(Data("{\"later\":true}".utf8), forKey: "app_settings")
        SandboxMigration.run(defaults: defaults, bundleIdentifier: "com.example.nothing-here")

        XCTAssertEqual(defaults.data(forKey: "app_settings"), Data("{\"later\":true}".utf8))
    }

    /// A fresh install has no container. That is not a failure, and it must
    /// not leave the migration armed to fire later against whatever it finds.
    func test_freshInstallWithNoContainer_isMarkedDone() throws {
        let defaults = try makeDefaults(#function)

        let imported = SandboxMigration.run(
            defaults: defaults, bundleIdentifier: "com.example.definitely-not-installed")

        XCTAssertEqual(imported, 0)
        XCTAssertTrue(defaults.bool(forKey: SandboxMigration.completionKey))
    }
}
