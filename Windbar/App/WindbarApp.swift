import SwiftUI

@main
struct WindbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel: AppModel

    /// True when `xcodebuild test` launched this app to host the test bundle.
    ///
    /// The unit tests live inside this app, so a test run starts the real
    /// thing. Without this the host would do a full startup on every run:
    /// read the login Keychain, sign in to Dreo and open a websocket. The
    /// tests themselves use fakes and want none of it, and the Keychain read
    /// is actively user-hostile, because a test build is ad-hoc signed rather
    /// than carrying the identity that item's ACL names, so macOS puts up
    /// "Windbar wants to use your confidential information" every single run.
    /// Running the suite a few times in a row, or rendering screenshots, turns
    /// that into a password prompt every few seconds.
    ///
    /// Read from the environment rather than by looking for XCTestCase: the
    /// test bundle is injected into an already-launched host, so the class is
    /// not reliably loaded yet at this point, but the variable is set on the
    /// host's environment before it starts.
    private static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        let model = AppModel()
        _appModel = State(initialValue: model)
        appDelegate.configure(appModel: model)

        guard !Self.isHostingTests else { return }

        #if WINDBAR_DIRECT
        // Before anything reads UserDefaults. The direct-download build is
        // unsandboxed so its updater can replace the app, which also moves
        // where macOS keeps its preferences, so the previous sandboxed
        // install's settings have to be carried across first. Reading
        // defaults ahead of this would see an empty store and treat a
        // long-time user as a fresh install.
        SandboxMigration.run()
        #endif

        Task { await model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appModel: appModel)
                .tint(Theme.accent)
        } label: {
            Image(systemName: appModel.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Add a Device", id: "add-device") {
            AddDeviceView(appModel: appModel)
                .tint(Theme.accent)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(appModel: appModel)
                .tint(Theme.accent)
        }
    }

}
