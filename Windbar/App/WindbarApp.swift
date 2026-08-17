import SwiftUI

@main
struct WindbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel: AppModel

    init() {
        #if WINDBAR_DIRECT
        // Before anything reads UserDefaults. The direct-download build is
        // unsandboxed so its updater can replace the app, which also moves
        // where macOS keeps its preferences, so the previous sandboxed
        // install's settings have to be carried across first. Reading
        // defaults ahead of this would see an empty store and treat a
        // long-time user as a fresh install.
        SandboxMigration.run()
        #endif

        let model = AppModel()
        _appModel = State(initialValue: model)
        appDelegate.configure(appModel: model)
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
