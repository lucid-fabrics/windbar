import Foundation
import KeyboardShortcuts

/// A proposed shortcut that clashes with one already bound to another name.
///
/// Shown inline inside the preset editor so the user knows exactly which
/// other trigger they would shadow, instead of letting the conflict surface
/// later as "why does my Office Fan key stop working".
struct ShortcutCollision: Equatable {
    let conflictingName: KeyboardShortcuts.Name
}

/// One place that knows every shortcut the app might bind. Used by the
/// preset editor to flag a proposed binding as a conflict against any of
/// these, including the per-fan power toggle and every other preset.
enum ShortcutRegistry {
    /// Names registered for the global toggle, every device currently on the
    /// account, and every preset that belongs to one of those devices.
    ///
    /// Scoped to `devices`, not to every key `presetsBySerialNumber` happens
    /// to have. Presets are deliberately kept in settings across a sign-out
    /// (so logging back into the same account gets them back), which means
    /// the dict can carry entries for a serial that belongs to a different
    /// account than the one now signed in. Enumerating the dict directly
    /// used to make those invisible presets count as live collisions: a
    /// shortcut would be refused as "conflicting" with a preset the user
    /// cannot see, cannot delete, and no longer has a device for.
    static func names(
        devices: [DreoDevice],
        presetsBySerialNumber: [String: [DevicePreset]]
    ) -> [KeyboardShortcuts.Name] {
        var names: [KeyboardShortcuts.Name] = [.toggleFanPower]
        for device in devices {
            names.append(.togglePower(deviceSerialNumber: device.serialNumber))
            for preset in presetsBySerialNumber[device.serialNumber] ?? [] {
                names.append(.preset(id: preset.id))
            }
        }
        return names
    }

    /// Returns a `ShortcutCollision` if `proposed` matches any name in
    /// `candidates` other than `exclude`. `exclude` is the name the user is
    /// currently editing, so re-saving the same preset does not flag
    /// itself.
    static func findCollision(
        proposed: KeyboardShortcuts.Shortcut,
        excluding exclude: KeyboardShortcuts.Name,
        candidates: [KeyboardShortcuts.Name]
    ) -> ShortcutCollision? {
        for candidate in candidates where candidate != exclude {
            if let bound = KeyboardShortcuts.getShortcut(for: candidate),
               bound == proposed {
                return ShortcutCollision(conflictingName: candidate)
            }
        }
        return nil
    }
}

extension KeyboardShortcuts.Name {
    /// Human-readable description of a shortcut binding. Used to tell the
    /// user which of their other shortcuts is in conflict without making
    /// them decode a `preset.<uuid>` raw value.
    var displayDescription: String {
        let raw = rawValue
        if raw == KeyboardShortcuts.Name.toggleFanPower.rawValue {
            return "Power (last used fan)"
        }
        if raw.hasPrefix("togglePower.") {
            return "Power"
        }
        if raw.hasPrefix("preset.") {
            return "another preset"
        }
        return raw
    }
}
