import SwiftUI

/// The top strip of a device card: icon, name + model + temperature, the
/// options menu and the power toggle. Kept out of `DeviceControlView` so that
/// file stays under the type-body-length budget; nothing about this header is
/// specific to one fan model.
struct DeviceHeaderView: View {
    let device: DreoDevice
    let onCopyTriggerLink: () -> Void
    let onCopyDeviceReport: () -> Void
    let onRemove: () -> Void
    let onTogglePower: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var iconTint: Color {
        guard device.isOnline else { return .secondary }
        return device.isOn ? Theme.accent : .secondary
    }

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: device.isOnline ? (device.isOn ? "fan.fill" : "fan") : "fan.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .symbolEffect(.variableColor.iterative, isActive: device.isOn && device.isOnline)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(device.deviceName)
                    .font(Theme.Font.deviceName)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if device.isOnline {
                        Text(device.model)
                        if let temperature = device.state["temperature"]?.intValue {
                            Text("·")
                            Text("\(temperature)°")
                                .monospacedDigit()
                        }
                    } else {
                        Text("Offline")
                            .foregroundStyle(.secondary)
                        Text("·")
                        Text(device.model)
                    }
                }
                .font(Theme.Font.deviceMeta)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.tight)

            DeviceOptionsMenu(
                deviceName: device.deviceName,
                onCopyTriggerLink: onCopyTriggerLink,
                onCopyDeviceReport: onCopyDeviceReport,
                onRemove: onRemove
            )

            Toggle("Power", isOn: Binding(
                get: { device.isOn },
                set: { _ in onTogglePower() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}
