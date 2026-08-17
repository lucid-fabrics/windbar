import Foundation
import KeyboardShortcuts

/// Keeps a keyboard shortcut handler registered for every device on the
/// account.
///
/// Devices only exist after the account has been loaded, so bindings cannot be
/// declared up front the way a fixed shortcut can. This binds each serial the
/// first time it is seen and remembers it, because registering the same name
/// twice would leave two handlers attached and toggle the fan back off again
/// on a single keypress.
@MainActor
final class DeviceShortcutBinder {
    private var boundSerialNumbers: Set<String> = []
    private var boundPresetIDs: Set<UUID> = []

    /// Binds anything not already bound. Safe to call on every refresh.
    ///
    /// Handlers are never removed: a shortcut belonging to a device that has
    /// since been removed just resolves to nothing, and rebinding it later
    /// would double up the handler.
    func bind(devices: [DreoDevice], toggle: @escaping @MainActor (String) -> Void) {
        for device in devices where !boundSerialNumbers.contains(device.serialNumber) {
            let serialNumber = device.serialNumber
            boundSerialNumbers.insert(serialNumber)

            KeyboardShortcuts.onKeyUp(for: .togglePower(deviceSerialNumber: serialNumber)) {
                Task { @MainActor in
                    toggle(serialNumber)
                }
            }
        }
    }

    /// Binds a key handler for each preset that has not yet been wired.
    /// Called whenever the user adds or saves a preset.
    func bindPresets(_ presets: [DevicePreset], apply: @escaping @MainActor (UUID) -> Void) {
        for preset in presets where !boundPresetIDs.contains(preset.id) {
            let id = preset.id
            boundPresetIDs.insert(id)

            KeyboardShortcuts.onKeyUp(for: .preset(id: id)) {
                Task { @MainActor in
                    apply(id)
                }
            }
        }
    }

    var boundCount: Int { boundSerialNumbers.count + boundPresetIDs.count }
}
