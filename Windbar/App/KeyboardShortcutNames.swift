import Foundation
import KeyboardShortcuts

// There is deliberately no "toggle whichever fan was used last" name here.
// One existed, bound at launch and listed as a collision candidate, but no
// view ever offered a recorder for it, so no user could assign it and it
// could never fire. Its only lasting effect was appearing in a collision
// message as a shortcut the user had never heard of. The equivalent for a
// macro key is still available, since `windbar://toggle` with no device
// parameter targets the last-used fan.
extension KeyboardShortcuts.Name {
    /// Toggles one specific device, so the bedroom fan and the office fan can
    /// each have their own key.
    ///
    /// The serial is part of the name, and that is what makes the binding
    /// stick across launches: a fan keeps its key, and a device that gets
    /// removed simply stops matching anything.
    static func togglePower(deviceSerialNumber: String) -> Self {
        Self("togglePower.\(deviceSerialNumber)")
    }

    /// Fires one preset. The UUID alone is enough because the binding is
    /// made after settings load, so the device is already known.
    static func preset(id: UUID) -> Self {
        Self("preset.\(id.uuidString)")
    }
}
