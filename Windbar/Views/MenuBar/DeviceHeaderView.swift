import SwiftUI

/// The top strip of a device card: icon, name, a line of state and the
/// power toggle. Kept out of `DeviceControlView` so that file
/// stays under the type-body-length budget; nothing about this header is
/// specific to one fan model.
///
/// It is also the whole of a collapsed card, which is what makes more than
/// two fans usable in a 320pt popover. Everything reached daily has to
/// survive the collapse: the power switch stays live, and the meta line
/// reports the fan (running or not, how fast, the room it sits in) whether
/// the card is open or not. A model code like DR-HEC005S says nothing to
/// someone looking at their fan; it lives in the device report instead.
struct DeviceHeaderView: View {
    let device: DreoDevice
    /// False only when this is the sole fan on the account. One device needs
    /// no accordion, and a disclosure chevron over a card that can never
    /// collapse is a control that does nothing.
    var isCollapsible = false
    var isExpanded = true
    /// Display unit for the reading below. Passed in rather than read from a
    /// shared settings object so this view stays previewable and testable.
    var temperatureUnit: TemperatureUnit = .automatic
    var onToggleExpanded: () -> Void = {}
    let onTogglePower: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var iconTint: Color {
        guard device.isOnline else { return .secondary }
        return device.isOn ? Theme.accent : .secondary
    }

    private var isSpinning: Bool { device.isOn && device.isOnline }

    /// One revolution every two seconds, phased off the wall clock so there
    /// is no per-view rotation state to start, stop or reset.
    static func spinAngle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) * 180
    }

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            if isCollapsible {
                // The chevron lives inside the button: it is the one part of
                // the row that advertises "this opens and closes", so a click
                // on it has to do exactly that.
                Button(action: onToggleExpanded) {
                    HStack(spacing: Theme.Space.snug) {
                        identity
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(.snappy(duration: 0.18), value: isExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse \(device.deviceName)" : "Expand \(device.deviceName)")
                .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            } else {
                identity
            }

            Toggle("Power", isOn: Binding(
                get: { device.isOn },
                set: { _ in onTogglePower() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("\(device.deviceName) power")
        }
    }

    private var identity: some View {
        HStack(spacing: Theme.Space.snug) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.18))
                    .frame(width: 30, height: 30)
                // A running fan spins. The variableColor "breathing" this
                // replaced read as the app being stuck on something, which is
                // the opposite of what a healthy running fan should say.
                // TimelineView rather than a repeatForever animation: pausing
                // freezes cleanly with no leftover animation state, and it
                // runs on macOS 14 where `.symbolEffect(.rotate)` does not.
                TimelineView(.animation(paused: !isSpinning)) { timeline in
                    Image(systemName: device.isOnline ? (device.isOn ? "fan.fill" : "fan") : "fan.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconTint)
                        .rotationEffect(.degrees(isSpinning ? Self.spinAngle(at: timeline.date) : 0))
                }
            }
            .overlay(alignment: .bottomTrailing) { waterBadge }

            VStack(alignment: .leading, spacing: 1) {
                Text(device.deviceName)
                    .font(Theme.Font.deviceName)
                    .lineLimit(1)
                meta
                    .monospacedDigit()
                    .font(Theme.Font.deviceMeta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)
        }
        .contentShape(Rectangle())
    }

    /// State, never identity: the same line open or closed, so opening a
    /// card never swaps what it says for a model code.
    ///
    /// One concatenated `Text` rather than an HStack of pieces: when the line
    /// is too long for the popover it loses its tail (the humidity) instead
    /// of every piece being cut to "Sp…". Most urgent first for that reason.
    private var meta: Text {
        guard device.isOnline else { return Text("Offline").foregroundStyle(.secondary) }
        var parts: [Text] = []
        if device.isWaterTankEmpty {
            parts.append(Text("\(Image(systemName: "drop.triangle.fill")) Tank empty").foregroundStyle(Theme.danger))
        }
        parts.append(Text(device.isOn ? runningSummary : "Off"))
        if device.isMisting && !device.isWaterTankEmpty { parts.append(Text("Misting")) }
        if let reading = device.state["temperature"]?.intValue {
            parts.append(Text(temperatureUnit.format(fahrenheit: reading)))
        }
        if let humidity = device.humidity { parts.append(Text("\(humidity)%")) }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text(" · ") + $1 }
    }

    /// A drop on the fan icon while it mists, red when the tank is dry, so
    /// the state reads from the icon alone as well as from the meta line.
    @ViewBuilder
    private var waterBadge: some View {
        if device.isOnline, device.isWaterTankEmpty || device.isMisting {
            Image(systemName: "drop.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(device.isWaterTankEmpty ? Theme.danger : Theme.accent)
                .padding(2)
                .background(Circle().fill(.background))
                .offset(x: 3, y: 3)
                .accessibilityHidden(true)
        }
    }

    /// "Speed 9" where the device publishes a speed control, plain "On"
    /// otherwise, since not every Dreo product has one.
    private var runningSummary: String {
        guard let speedSection = (device.controlsConf?.control ?? []).first(where: { $0.type == "Speed" }),
              let cmd = speedSection.items?.first?.cmd,
              let level = device.state[cmd]?.intValue else { return "On" }
        return "\((speedSection.title ?? "Speed").dreoTitleCased) \(level)"
    }
}
