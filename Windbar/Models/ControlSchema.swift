import Foundation

/// Mirrors the `controlsConf` object the Dreo API returns per device. This is
/// the server's own UI schema (modes, speed range, oscillation angles, etc),
/// so the app renders controls generically from it instead of hardcoding
/// behavior per model.
struct ControlSchema: Codable, Equatable, Sendable {
    var control: [ControlSection]
    var preference: [ControlSection]

    /// True when the server sent no renderable controls at all. Happens for
    /// a device that was only just provisioned, whose `controlsConf` comes
    /// back holding nothing but a `template` field.
    var isEmpty: Bool { control.isEmpty && preference.isEmpty }

    init(control: [ControlSection] = [], preference: [ControlSection] = []) {
        self.control = control
        self.preference = preference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        control = container.decodeLossyArray(ControlSection.self, forKey: .control)
        preference = container.decodeLossyArray(ControlSection.self, forKey: .preference)
    }
}

struct ControlSection: Codable, Equatable, Identifiable, Sendable {
    let rawId: String?
    let type: String
    let title: String?
    let cmd: String?
    let items: [ControlItem]?

    /// Preference toggles only. Some read inverted, e.g. `muteon` is true
    /// when panel sound is *off*, so the switch has to be flipped to match
    /// what the label says.
    let reverse: Bool?
    /// Values to send for on/off when the device uses ints rather than
    /// booleans, e.g. `lightmode` where 0 means the display auto-offs.
    let trueValue: DreoValue?
    let falseValue: DreoValue?

    /// A switch that has to be on for this section to do anything, e.g. the
    /// light ring's own power for its colour and brightness.
    ///
    /// Without it a control looks broken rather than inert: the fan accepts a
    /// colour while the ring is off, answers that it applied it, and nothing
    /// lights up. Using the control turns its prerequisite on first, the same
    /// way running a preset turns the fan on.
    let requires: String?

    var id: String { rawId ?? cmd ?? type }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case type, title, cmd, items, reverse, trueValue, falseValue, requires
    }
}

struct ControlItem: Codable, Equatable, Identifiable, Sendable {
    let text: String
    let cmd: String
    let value: DreoValue

    var id: String { "\(cmd)_\(value)" }
}
