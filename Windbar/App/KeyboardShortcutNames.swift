import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggles whichever device was used last. Kept for anyone who owns one
    /// fan, or who wants a single key that follows them around.
    static let toggleFanPower = Self("toggleFanPower")

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
