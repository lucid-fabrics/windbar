import Foundation

/// The countdown a Dreo fan runs on its own: switch on (`timeron`) or off
/// (`timeroff`) after a number of minutes.
///
/// The fan keeps the clock, not this app, so a timer still fires with the
/// Mac asleep or Windbar quit. Both keys carry `{"du": minutes, "ts":
/// epochSeconds}`, and `du` 0 cancels. Wire format per hass-dreo
/// (`pydreofanbase.py`), which drives these keys on every fan that reports
/// them and caps `du` at 719.
struct FanTimer: Equatable {
    enum Kind: String, CaseIterable {
        case turnOn = "timeron"
        case turnOff = "timeroff"
    }

    let kind: Kind
    let endsAt: Date

    /// hass-dreo's ceiling, just under twelve hours.
    static let maxMinutes = 719

    /// The durations offered on the card, in minutes. 0 is "no timer".
    static let presets = [0, 30, 60, 120, 240, 480]

    /// The command that arms (or, with 0 minutes, cancels) a timer.
    static func command(_ kind: Kind, minutes: Int, now: Date = Date()) -> (key: String, value: DreoValue) {
        let clamped = min(max(minutes, 0), maxMinutes)
        return (kind.rawValue, .object([
            "ts": .int(Int(now.timeIntervalSince1970)),
            "du": .int(clamped)
        ]))
    }

    /// Reads a timer from the fan's state, or nil when none is running.
    ///
    /// The end time is `ts + du` minutes. Whether the fan reports `du` as the
    /// original duration with `ts` as the moment it was set, or as minutes
    /// left with `ts` as the moment of the report, both land on the same
    /// end, so either reading gives the right answer. A timer whose end has
    /// passed is treated as gone, since the fan may not report the reset
    /// before the card is next looked at.
    static func active(in state: [String: DreoValue], now: Date = Date()) -> FanTimer? {
        for kind in Kind.allCases {
            guard let fields = state[kind.rawValue]?.objectValue,
                  let minutes = fields["du"]?.intValue, minutes > 0 else { continue }
            var stamp = fields["ts"]?.intValue ?? 0
            // Seconds everywhere seen so far; a millisecond stamp would put
            // the end thousands of years out, so normalise it rather than
            // trust it.
            if stamp > 100_000_000_000 { stamp /= 1000 }
            let start = stamp > 0 ? Date(timeIntervalSince1970: TimeInterval(stamp)) : now
            let end = start.addingTimeInterval(TimeInterval(minutes * 60))
            if end > now { return FanTimer(kind: kind, endsAt: end) }
        }
        return nil
    }

    /// Whether this fan has the countdown at all. Only fans that report the
    /// keys get the control, same rule hass-dreo applies.
    static func isSupported(by state: [String: DreoValue]) -> Bool {
        Kind.allCases.contains { state[$0.rawValue]?.objectValue != nil }
    }

    /// "Off at 5:40 PM": a clock time rather than a countdown, so it stays
    /// true without the card redrawing every minute.
    var summary: String {
        let time = endsAt.formatted(date: .omitted, time: .shortened)
        return kind == .turnOn ? "On at \(time)" : "Off at \(time)"
    }

    /// Chip caption for a preset duration.
    static func label(minutes: Int) -> String {
        if minutes == 0 { return "None" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}
