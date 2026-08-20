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

    /// Range-style items carry bounds instead of one discrete value. A
    /// ceiling fan's lamp describes its brightness as `minValue` 1 to
    /// `maxValue` 100 with no `value` at all, and requiring one silently
    /// dropped the whole light section from those fans.
    let minValue: Int?
    let maxValue: Int?
    /// The vendor's kind tag on range items: "light" for a dimmer, "color"
    /// for a colour-temperature ramp. Discrete items do not carry it.
    let itemType: String?

    var id: String { "\(cmd)_\(value)" }

    var range: ClosedRange<Int>? {
        guard let minValue, let maxValue, minValue < maxValue else { return nil }
        return minValue...maxValue
    }

    /// Slider caption for a range item. The vendor reuses unrelated mode
    /// strings in these items' `text` ("Natural" on a dimmer), so the kind
    /// tag is the only field that says what the slider actually does.
    var rangeTitle: String {
        switch itemType {
        case "light": return "Brightness"
        case "color": return "Color Temperature"
        default: return cmd.dreoTitleCased
        }
    }

    enum CodingKeys: String, CodingKey {
        case text, cmd, value, minValue, maxValue
        case itemType = "type"
    }

    init(
        text: String,
        cmd: String,
        value: DreoValue,
        minValue: Int? = nil,
        maxValue: Int? = nil,
        itemType: String? = nil
    ) {
        self.text = text
        self.cmd = cmd
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.itemType = itemType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        cmd = try container.decode(String.self, forKey: .cmd)
        minValue = try container.decodeIfPresent(Int.self, forKey: .minValue)
        maxValue = try container.decodeIfPresent(Int.self, forKey: .maxValue)
        itemType = try container.decodeIfPresent(String.self, forKey: .itemType)
        // A range item has no discrete value; its lower bound stands in so
        // `id` and every site that only reads `cmd` keep working unchanged.
        // An item with neither is genuinely malformed and throws, which the
        // lossy section decode turns into a dropped section rather than a
        // phantom chip that would send 0 to the fan.
        guard let resolved = try container.decodeIfPresent(DreoValue.self, forKey: .value)
                ?? minValue.map(DreoValue.int) else {
            throw DecodingError.keyNotFound(CodingKeys.value, .init(
                codingPath: decoder.codingPath,
                debugDescription: "control item has neither value nor minValue"
            ))
        }
        value = resolved
    }
}
