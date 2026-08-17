import Foundation
import os

/// Carries settings out of the old sandbox container on first unsandboxed launch.
///
/// The direct-download build drops the App Store sandbox, because a
/// sandboxed app is not allowed to replace itself in /Applications and the
/// updater therefore cannot work at all. Dropping it moves where macOS keeps
/// the app's preferences: a sandboxed app reads
/// `~/Library/Containers/<bundle id>/Data/Library/Preferences/<bundle id>.plist`,
/// an unsandboxed one reads `~/Library/Preferences/<bundle id>.plist`. Same
/// app, same bundle id, different file.
///
/// Without this, updating to the first unsandboxed build looks exactly like a
/// fresh install: presets gone along with the keyboard shortcuts bound to
/// them, the last-used fan forgotten, the first-run wizard back, and every
/// donation forgotten, so someone who has already paid starts being asked
/// again. That last one is the reason this runs before anything reads
/// defaults.
///
/// Compiled only into the direct-download build. The App Store build keeps
/// its sandbox and its container, and must never touch either path.
///
/// What this deliberately does NOT carry across is the Dreo password. That
/// lives in the login Keychain rather than in preferences, and a Keychain
/// item's ACL is tied to the signature of the app that created it. The two
/// builds are signed with different certificates, so macOS treats them as
/// different applications: moving between them produces a "Windbar wants to
/// use your confidential information" prompt, or the item simply is not
/// offered at all.
///
/// Left alone on purpose. Sharing it means either a shared Keychain access
/// group, which widens access to a real password for everyone including App
/// Store users, or asking for the login Keychain password to copy it.
/// Signing in to Dreo once is the smaller ask, and `loadCredentials` already
/// returns nil and lands on the login screen, so the worst case is a login
/// prompt rather than anything broken. Worth a line in the release notes.
enum SandboxMigration {
    private static let logger = Logger(subsystem: "com.lucidfabrics.windbar", category: "SandboxMigration")

    /// Set once the container has been read, so this is a one-time import
    /// rather than something that keeps overwriting live settings with a
    /// stale copy every launch.
    static let completionKey = "didImportSandboxContainer"

    /// Everything worth carrying across. Window frames and other AppKit
    /// bookkeeping are deliberately left behind: they are noise, and a
    /// restored frame from a differently-shaped build is worse than a
    /// default one.
    ///
    /// `KeyboardShortcuts_` is a prefix rather than a key, since every bound
    /// shortcut is its own entry and the whole point of the migration is that
    /// a preset arriving without its key is only half a preset.
    static let keys = ["app_settings", "donationState"]
    static let keyPrefixes = ["KeyboardShortcuts_"]

    static func containerPreferencesURL(bundleIdentifier: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)")
            .appendingPathComponent("Data/Library/Preferences/\(bundleIdentifier).plist")
    }

    /// Copies anything worth keeping out of the container, once.
    ///
    /// Deliberately never overwrites a value that already exists: someone who
    /// has been running an unsandboxed build already has the real settings in
    /// the new location, and the container copy is the stale one. Existing
    /// data wins over imported data, always.
    @discardableResult
    static func run(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.lucidfabrics.windbar",
        fileManager: FileManager = .default
    ) -> Int {
        guard !defaults.bool(forKey: completionKey) else { return 0 }

        let url = containerPreferencesURL(bundleIdentifier: bundleIdentifier)
        guard fileManager.fileExists(atPath: url.path) else {
            // No container: a genuinely fresh install, or an App Store user
            // who never had one. Mark it done so this never runs again.
            defaults.set(true, forKey: completionKey)
            return 0
        }

        guard let data = try? Data(contentsOf: url),
              let container = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any] else {
            logger.warning("Container preferences unreadable at \(url.path, privacy: .public)")
            // Not marked done: an unreadable file today might be readable
            // next launch, and giving up permanently on one bad read would
            // strand the user's data for good.
            return 0
        }

        var imported = 0
        for (key, value) in container where shouldImport(key) {
            guard defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            imported += 1
        }

        defaults.set(true, forKey: completionKey)
        logger.notice("Imported \(imported, privacy: .public) settings from the sandbox container")
        return imported
    }

    static func shouldImport(_ key: String) -> Bool {
        keys.contains(key) || keyPrefixes.contains { key.hasPrefix($0) }
    }
}
