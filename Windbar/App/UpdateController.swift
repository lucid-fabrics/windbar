#if WINDBAR_DIRECT
import Foundation
import Observation
import Sparkle

/// In-app updates for the direct-download build.
///
/// This whole file compiles to nothing in the App Store build. Apple ships
/// those updates itself and rejects an app that updates itself, which is the
/// same shape of problem as the donation code: the shipped App Store binary
/// must not contain this, not merely avoid calling it. `release_dmg` sets
/// `WINDBAR_DIRECT`, the `release` lane never does, and it greps the finished
/// archive to prove the difference rather than trusting the flag.
///
/// Everyone who downloaded the DMG gets these updates, not only people who
/// donated. A bug fix that reaches only the people who paid is a bug
/// knowingly left in everyone else's app, and since the DMG sits on a public
/// releases page anyone can fetch the new version in thirty seconds anyway,
/// gating it would produce an inconvenience rather than a privilege. The
/// supporter's actual perk is that the app stops asking them for money.
///
/// Deliberately thin. Sparkle already owns the update dialog, the release
/// notes, the download progress and the restart, and every one of those is a
/// thing macOS users already recognise from other apps. Reimplementing any of
/// it would mean maintaining a worse copy that drifts.
@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true begins the scheduled background checks, whose
        // interval and opt-out live in Sparkle's own defaults. No forced
        // install and no silent restart: it asks, every time.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// The footer's "Check for Updates…", for anyone who would rather look
    /// than wait for the scheduled check.
    ///
    /// Always callable, and deliberately not disabled while a check is
    /// running. Sparkle no-ops safely in that case, and its
    /// `canCheckForUpdates` is KVO-published, which `@Observable` does not
    /// bridge, so gating the row on it would mean polling to keep a
    /// disabled state honest for the second or two it is ever false.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
#endif
