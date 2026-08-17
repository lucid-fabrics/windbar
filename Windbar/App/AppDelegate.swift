import AppKit
import KeyboardShortcuts

/// Owns the `windbar://` URL scheme, which is how anything outside the menu
/// bar dropdown drives a fan: a Stream Deck button, a Corsair G-key, an
/// Elgato pedal. Keyboard shortcuts are bound per fan by
/// `DeviceShortcutBinder` instead, from the card that shows them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appModel: AppModel?

    func configure(appModel: AppModel) {
        self.appModel = appModel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Stops macOS opening a window just because the app was activated.
    ///
    /// This app lives in the menu bar and has exactly one window scene, the
    /// pairing wizard. Triggering `windbar://toggle` activates the app, and
    /// without this the activation was answered by opening that wizard, so
    /// pressing the hotkey toggled the fan and threw up a setup dialog at the
    /// same time.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The wizard's frame gets persisted, and a restored frame is enough
        // for macOS to bring the window back on a later launch. Nothing here
        // is worth restoring: the menu bar is the entry point.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    /// Handles `windbar://toggle`, and `windbar://toggle?device=<serial>` for
    /// a specific fan.
    ///
    /// The per-device form exists because macro keys cannot be recorded as
    /// shortcuts: a Corsair G-key, a Stream Deck button or an Elgato pedal is
    /// swallowed by its own software and never reaches this app as a
    /// keystroke. Those tools can all launch a URL, so this is how they aim
    /// at one fan instead of whichever was touched last.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model = appModel else { return }
        for url in urls where url.scheme == "windbar" {
            handle(url, with: model)
        }
    }

    /// Routes one `windbar://` URL.
    ///
    /// - `toggle` flips power, on `device` or on the last-used fan.
    /// - `set` writes one control, e.g. `key=windlevel&value=9`.
    /// - `adjust` nudges a numeric control, e.g. `key=windlevel&delta=-1`.
    /// - `preset` runs a saved preset, e.g. `device=<serial>&preset=<uuid>`,
    ///   and turns the fan off if that preset is the one already running.
    private func handle(_ url: URL, with model: AppModel) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        let device = value("device")
        let key = value("key")

        Task { @MainActor in
            switch url.host {
            case "toggle":
                if let device {
                    model.togglePower(serialNumber: device)
                } else {
                    model.toggleLastSelectedDevicePower()
                }

            case "set":
                guard let device, let key, let raw = value("value") else { return }
                model.setValue(Self.parse(raw), forKey: key, onSerialNumber: device)

            case "adjust":
                guard let device, let key, let delta = value("delta").flatMap(Int.init) else { return }
                model.adjustValue(forKey: key, by: delta, onSerialNumber: device)

            case "preset":
                guard let device,
                      let raw = value("preset"),
                      let id = UUID(uuidString: raw) else { return }
                model.firePreset(id: id, onSerialNumber: device)

            default:
                break
            }
        }
    }

    /// URLs carry everything as text, so a value has to be read back into the
    /// type the device expects.
    private static func parse(_ raw: String) -> DreoValue {
        if let number = Int(raw) { return .int(number) }
        switch raw.lowercased() {
        case "true", "on", "yes": return .bool(true)
        case "false", "off", "no": return .bool(false)
        default: return .string(raw)
        }
    }
}
