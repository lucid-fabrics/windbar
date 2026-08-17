import AppKit
import KeyboardShortcuts
import SwiftUI

/// Every keyboard shortcut for one fan, in one list on its card.
///
/// These used to be two features in two places: a "Toggle Power" recorder
/// buried in More options, and preset rows here. Since running a preset a
/// second time turns the fan off, the two look like the same thing most of
/// the time, and their one real difference was written down nowhere. Power
/// resumes the fan exactly as it was, whatever you last nudged by hand; a
/// preset forces its saved shape every time. Same list, and the Power row
/// says which it is, so the choice is made where the difference is visible.
struct ShortcutsSection: View {
    let appModel: AppModel
    let device: DreoDevice
    let presets: [DevicePreset]
    let onEdit: (DevicePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            SectionLabel(title: "Shortcuts")

            VStack(spacing: 1) {
                powerRow

                ForEach(presets) { preset in
                    ShortcutRow(
                        icon: appModel.isActive(preset, on: device) ? "stop.fill" : "play.fill",
                        iconIsAccented: appModel.isActive(preset, on: device),
                        title: preset.name,
                        subtitle: summary(for: preset),
                        isActive: appModel.isActive(preset, on: device),
                        shortcutName: .preset(id: preset.id),
                        allShortcutNames: allShortcutNames,
                        help: appModel.isActive(preset, on: device)
                            ? "Turn off \(preset.name)"
                            : "Run \(preset.name)",
                        onTrigger: { appModel.fire(preset, on: device) },
                        onCollision: reportCollision,
                        onEdit: { onEdit(preset) },
                        onDelete: { confirmDelete(preset) }
                    )
                }
            }
        }
        // Same local-event-monitor constraint as every recorder in the
        // popover: each only sees keystrokes while this app is active, so
        // activating once when the section appears keeps them all usable.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    /// The built-in first row. Deliberately not tinted when the fan is on,
    /// unlike a running preset: the header's power switch already states
    /// that loudly, while which named shape is running is information the
    /// tint is the only carrier of. The icon still takes the accent, so the
    /// row is not silent about it either.
    private var powerRow: some View {
        ShortcutRow(
            icon: "power",
            iconIsAccented: device.isOn,
            title: "Power",
            subtitle: "On / off · keeps current settings",
            isActive: false,
            shortcutName: .togglePower(deviceSerialNumber: device.serialNumber),
            allShortcutNames: allShortcutNames,
            help: device.isOn ? "Turn \(device.deviceName) off" : "Turn \(device.deviceName) on",
            onTrigger: { appModel.togglePower(for: device) },
            onCollision: reportCollision,
            onEdit: nil,
            onDelete: nil
        )
    }

    private func reportCollision(_ collision: ShortcutCollision) {
        appModel.errorMessage =
            "That shortcut is already used by \(collision.conflictingName.displayDescription)."
    }

    /// Every other bound shortcut, for each row recorder's collision check.
    /// The preset editor blocks a colliding combo before Save is enabled; a
    /// row records live, so it has to undo what was typed instead.
    private var allShortcutNames: [KeyboardShortcuts.Name] {
        ShortcutRegistry.names(
            devices: appModel.devices,
            presetsBySerialNumber: appModel.settings.presetsBySerialNumber
        )
    }

    /// Mirrors `DeviceControlView.confirmRemoval()`: a real window-level
    /// alert rather than a SwiftUI confirmation dialog, since the popover
    /// closes the instant it loses focus and would take a SwiftUI dialog
    /// down with it. Deleting a preset drops a named shape and a bound
    /// keyboard shortcut in one click; a device removal gets exactly this much
    /// ceremony, and a preset deserved no less.
    private func confirmDelete(_ preset: DevicePreset) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \"\(preset.name)\"?"
        alert.informativeText = "This removes the preset and its keyboard shortcut. This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        // Return picks Cancel, so leaning on the keyboard cannot delete a
        // preset by accident.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        appModel.removePreset(id: preset.id, on: device)
    }

    /// One line saying what the preset does, worded from the device's own
    /// schema ("Speed 12 · Sleep · Osc 120°"), so a row is recognisable
    /// without opening it.
    private func summary(for preset: DevicePreset) -> String? {
        let values = preset.values
        var parts: [String] = []
        for section in device.controlsConf?.control ?? [] {
            switch section.type {
            case "Speed":
                // The section's own title, not a fixed "Speed" literal: a
                // device with two step-slider sections sharing this type
                // (a fan speed and, on an earlier shape of the light speed
                // control, a light speed) made them indistinguishable in a
                // summary like "Speed 4 · Speed 7". The device's own title
                // for each section is what tells them apart, and it says
                // "Speed" for an ordinary single-speed device same as before.
                if let cmd = section.items?.first?.cmd, let level = values[cmd]?.intValue {
                    parts.append("\(sectionTitle(section)) \(level)")
                }
            case "Oscillation":
                guard let cmd = section.cmd, let isOn = values[cmd]?.boolValue else { break }
                if !isOn {
                    parts.append("Osc off")
                } else if let item = section.items?.first(where: { values[$0.cmd] == $0.value }) {
                    parts.append("Osc \(item.text.dreoTitleCased)")
                } else {
                    parts.append("Osc on")
                }
            default:
                if let item = section.items?.first(where: { values[$0.cmd] == $0.value }) {
                    parts.append(item.text.dreoTitleCased)
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sectionTitle(_ section: ControlSection) -> String {
        (section.title ?? section.type).dreoTitleCased
    }
}

/// One row: an icon saying what a click does, a name, a line of detail, the
/// recorder for its key, and an options menu where there is something to
/// edit. Power and presets share it so the two read as one list rather than
/// two features that happen to sit near each other.
private struct ShortcutRow: View {
    let icon: String
    let iconIsAccented: Bool
    let title: String
    let subtitle: String?
    let isActive: Bool
    let shortcutName: KeyboardShortcuts.Name
    let allShortcutNames: [KeyboardShortcuts.Name]
    let help: String
    let onTrigger: () -> Void
    let onCollision: (ShortcutCollision) -> Void
    /// Both nil for the built-in Power row: there is no shape to edit and
    /// nothing to delete, so it carries no menu rather than a disabled one.
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    /// Name and recorder share the top line; the detail line runs full width
    /// underneath, indented to sit under the name.
    ///
    /// An unrecorded shortcut renders as a "Record Shortcut" button roughly
    /// 170pt wide, which in a 320pt popover left about 80pt for text beside
    /// it. Everything useful was an ellipsis: the Power row's own
    /// explanation, the whole reason this list exists, came out as
    /// "On / off · ke…". Names are short and survive sharing the line;
    /// sentences do not.
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Space.tight) {
                Button(action: onTrigger) {
                    HStack(spacing: Theme.Space.tight) {
                        Image(systemName: icon)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(iconIsAccented ? Theme.accent : Color.secondary)
                            .frame(width: 10)
                        Text(title)
                            .font(Theme.Font.body)
                            .fontWeight(isActive ? .semibold : .regular)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)

                KeyboardShortcuts.Recorder(for: shortcutName) { newValue in
                    guard let newValue,
                          let collision = ShortcutRegistry.findCollision(
                              proposed: newValue,
                              excluding: shortcutName,
                              candidates: allShortcutNames
                          )
                    else { return }
                    // The preset editor blocks Save on a collision before
                    // anything is written; a row records live, so the only
                    // way to "block" here is to undo what was typed and say
                    // why.
                    KeyboardShortcuts.setShortcut(nil, for: shortcutName)
                    onCollision(collision)
                }
                .controlSize(.small)

                if let onEdit, let onDelete {
                    Menu {
                        Button("Edit…", action: onEdit)
                        Divider()
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Preset options")
                } else {
                    // Keeps every row's recorder on the same vertical line:
                    // the Power row has no menu, and without this its
                    // recorder would sit a menu-width right of the rows below.
                    Color.clear.frame(width: 22, height: 20)
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Indented past the icon so it reads as belonging to the
                    // name above it rather than starting a new column.
                    .padding(.leading, 10 + Theme.Space.tight)
            }
        }
        .padding(.horizontal, Theme.Space.tight)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.controlRadius, style: .continuous)
                // A tint rather than a solid accent fill. A full-width slab
                // of accent would outweigh the speed and mode controls above
                // it, and the row is a peer of those, not their headline.
                .fill(rowFill)
        )
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.18), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var rowFill: Color {
        if isActive { return Theme.accentTint(scheme) }
        // Hover stays neutral grey, so blue never means anything but active.
        return isHovering ? Theme.surfaceRaised(scheme) : .clear
    }
}
