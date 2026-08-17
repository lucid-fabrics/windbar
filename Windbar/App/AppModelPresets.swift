import Foundation
import KeyboardShortcuts

extension AppModel {
    // MARK: - Presets

    /// Whether the fan is currently running this preset, which is what makes
    /// one visibly active in the list and what turns its own trigger into an
    /// off switch.
    ///
    /// Only the keys the preset stores are compared, so a preference the
    /// user changed elsewhere never blocks a match. Anything else, including
    /// a value nudged by hand, means no preset is active, which is honest:
    /// the fan is no longer in a shape anyone named.
    func isActive(_ preset: DevicePreset, on device: DreoDevice) -> Bool {
        guard device.isOn else { return false }
        let shape = preset.shape(powerKey: device.powerKey)
        guard !shape.isEmpty else { return false }
        return shape.allSatisfy { device.state[$0.key] == $0.value }
    }

    /// The one preset the fan is currently running, if any.
    func activePreset(on device: DreoDevice) -> DevicePreset? {
        settings.presetsBySerialNumber[device.serialNumber]?
            .first { isActive($0, on: device) }
    }

    /// What every trigger does: a click on the row, the keyboard shortcut and
    /// the URL all land here so a preset behaves the same however it is
    /// fired. Running the preset the fan is already in turns the fan off, so
    /// one key is both "north on" and "north off".
    func fire(_ preset: DevicePreset, on device: DreoDevice) {
        if isActive(preset, on: device) {
            setValue(.bool(false), forKey: device.powerKey, on: device)
        } else {
            apply(preset: preset, on: device)
        }
    }

    /// Turns the fan on and puts it in the preset's shape. Power leads, and
    /// the rest follows the device's own schema order, prerequisite before
    /// dependent, so two runs of the same preset send the same sequence.
    ///
    /// Alphabetical order used to decide this, and it was wrong: the light's
    /// controls are gated behind `atmon` by `requires`, and alphabetically
    /// atmbri < atmcolor < atmmode < atmon, so three of four could land while
    /// the ring was still off and the fan would apply everything but the
    /// colour on the first run of a light preset.
    func apply(preset: DevicePreset, on device: DreoDevice) {
        let shape = preset.shape(powerKey: device.powerKey)
        var commands: [(key: String, value: DreoValue)] = [(device.powerKey, .bool(true))]
        commands += orderedKeys(for: shape, on: device).map { (key: $0, value: shape[$0]!) }
        send(commands, to: device)
    }

    /// Orders a set of keys the way the device's own control schema presents
    /// them, a section's `requires` target always ahead of the section that
    /// depends on it. A key the schema doesn't mention (a stale value from a
    /// template that changed) is not dropped, just sent last, in a stable
    /// order.
    private func orderedKeys(for shape: [String: DreoValue], on device: DreoDevice) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        func add(_ key: String) {
            guard shape[key] != nil, !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(key)
        }

        for section in device.controlsConf?.control ?? [] {
            if let required = section.requires { add(required) }
            if let cmd = section.cmd { add(cmd) }
            for item in section.items ?? [] { add(item.cmd) }
        }
        for key in shape.keys.sorted() { add(key) }
        return ordered
    }

    /// Keyboard/URL entry point. Bails silently if the device is gone or
    /// unreachable, since a keypress has nowhere to surface an error.
    func firePreset(id: UUID, onSerialNumber serialNumber: String) {
        guard let device = devices.first(where: { $0.serialNumber == serialNumber }),
              device.isOnline,
              let preset = settings.presetsBySerialNumber[serialNumber]?
                  .first(where: { $0.id == id }) else { return }
        fire(preset, on: device)
    }

    /// Upserts by id: the editor owns the preset's identity, so saving an
    /// edited preset replaces it in place and saving a new one appends.
    /// Matching by id rather than name means the keyboard shortcut recorded
    /// under that id always stays attached to the row the user saved.
    func savePreset(_ preset: DevicePreset, on device: DreoDevice) {
        var stored = preset
        // Power is not part of a shape. Stripping it here as well as in the
        // editor keeps it out no matter which caller saved.
        stored.values = preset.shape(powerKey: device.powerKey)

        var list = settings.presetsBySerialNumber[device.serialNumber] ?? []
        if let index = list.firstIndex(where: { $0.id == stored.id }) {
            list[index] = stored
        } else {
            list.append(stored)
        }
        settings.presetsBySerialNumber[device.serialNumber] = list
        rebindPresets()
    }

    func removePreset(id: UUID, on device: DreoDevice) {
        guard var list = settings.presetsBySerialNumber[device.serialNumber] else { return }
        list.removeAll { $0.id == id }
        settings.presetsBySerialNumber[device.serialNumber] = list
        // Free the key combo so it can be given to another preset without
        // the collision check flagging a row that no longer exists.
        KeyboardShortcuts.reset(.preset(id: id))
    }

    /// Clears the stored key combo for every preset on one device. Used when
    /// the device itself is removed, so the combo can be reused rather than
    /// sitting claimed by a preset nothing can ever reach again.
    func unbindPresets(forSerialNumber serialNumber: String) {
        for preset in settings.presetsBySerialNumber[serialNumber] ?? [] {
            KeyboardShortcuts.reset(.preset(id: preset.id))
        }
    }

    /// Re-binds every preset shortcut across all devices. Called once after
    /// settings load and again whenever the preset list changes.
    func rebindPresets() {
        let allPresets = settings.presetsBySerialNumber.values.flatMap { $0 }
        shortcutBinder.bindPresets(allPresets) { [weak self] id in
            guard let self else { return }
            // Look up which device owns this preset by id, then route
            // through the offline-guarded entry point.
            guard let entry = self.settings.presetsBySerialNumber
                .first(where: { $0.value.contains(where: { $0.id == id }) })
            else { return }
            self.firePreset(id: id, onSerialNumber: entry.key)
        }
    }
}
