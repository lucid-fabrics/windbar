import SwiftUI

/// The top strip of a device card: icon, name, a line of state, the options
/// menu and the power toggle. Kept out of `DeviceControlView` so that file
/// stays under the type-body-length budget; nothing about this header is
/// specific to one fan model.
///
/// It is also the whole of a collapsed card, which is what makes more than
/// two fans usable in a 320pt popover. Everything reached daily has to
/// survive the collapse: the power switch stays live, and the meta line
/// switches from identifying the fan (model, which never changes) to
/// reporting it (running or not, how fast), because that is the thing worth
/// knowing at a glance about a fan you are not currently adjusting.
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
    let onCopyTriggerLink: () -> Void
    let onCopyDeviceReport: () -> Void
    let onRemove: () -> Void
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse \(device.deviceName)" : "Expand \(device.deviceName)")
                .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            } else {
                identity
            }

            // Hidden while collapsed: everything behind it (trigger link,
            // diagnostics, removal) is a deliberate, occasional action, and a
            // collapsed row earns its keep by being scannable.
            if isExpanded {
                DeviceOptionsMenu(
                    deviceName: device.deviceName,
                    onCopyTriggerLink: onCopyTriggerLink,
                    onCopyDeviceReport: onCopyDeviceReport,
                    onRemove: onRemove
                )
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

            VStack(alignment: .leading, spacing: 1) {
                Text(device.deviceName)
                    .font(Theme.Font.deviceName)
                    .lineLimit(1)
                meta
                    .font(Theme.Font.deviceMeta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)
        }
        .contentShape(Rectangle())
    }

    /// Expanded, the controls below already say what the fan is doing, so the
    /// meta line identifies it instead. Collapsed, they are gone and this line
    /// is all that is left, so it reports state.
    @ViewBuilder
    private var meta: some View {
        if !device.isOnline {
            HStack(spacing: 5) {
                Text("Offline").foregroundStyle(.secondary)
                Text("·")
                Text(device.model)
            }
        } else if isExpanded {
            HStack(spacing: 5) {
                Text(device.model)
                temperature
            }
        } else {
            HStack(spacing: 5) {
                Text(device.isOn ? runningSummary : "Off")
                    .monospacedDigit()
                temperature
            }
        }
    }

    /// The fan sends Fahrenheit; `temperatureUnit` decides what is shown.
    @ViewBuilder
    private var temperature: some View {
        if let reading = device.state["temperature"]?.intValue {
            Text("·")
            Text(temperatureUnit.format(fahrenheit: reading)).monospacedDigit()
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
