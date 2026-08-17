import AppKit
import KeyboardShortcuts
import SwiftUI

/// The preset list on the device card. Sits with the controls that made it
/// rather than behind "More options", because a preset someone uses daily
/// should be one click from the menu bar, and binding a key next to the fan
/// it belongs to means never hunting for which row is which device.
struct PresetsSection: View {
    let appModel: AppModel
    let device: DreoDevice
    let presets: [DevicePreset]
    let onEdit: (DevicePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            SectionLabel(title: "Presets")

            VStack(spacing: 1) {
                ForEach(presets) { preset in
                    PresetRow(
                        preset: preset,
                        summary: summary(for: preset),
                        isActive: appModel.isActive(preset, on: device),
                        allShortcutNames: allShortcutNames,
                        onTrigger: { appModel.fire(preset, on: device) },
                        onEdit: { onEdit(preset) },
                        onDelete: { confirmDelete(preset) },
                        onCollision: { collision in
                            appModel.errorMessage =
                                "That shortcut is already used by \(collision.conflictingName.displayDescription)."
                        }
                    )
                }
            }
        }
        // Same local-event-monitor constraint as the per-device power
        // shortcut: each recorder only sees keystrokes while this app is
        // active, so activating once when the section appears keeps every
        // recorder in the popover usable.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Every other bound shortcut, for the row recorder's own collision
    /// check. The editor already blocks a colliding combo before Save is
    /// even enabled; the row recorder is a second, independent place to
    /// bind a key and had no such check at all, so two live registrations of
    /// the same combo (one of them silently losing every press to whichever
    /// handler runs first) was one rebind away for anyone using it.
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
    /// global hotkey in one click; a device removal gets exactly this much
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

/// One row in the list. The whole row is the trigger, and the icon says what
/// the next click will do: play to run this shape, stop to shut the fan down
/// when it is already running it.
private struct PresetRow: View {
    let preset: DevicePreset
    let summary: String?
    let isActive: Bool
    let allShortcutNames: [KeyboardShortcuts.Name]
    let onTrigger: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCollision: (ShortcutCollision) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            Button(action: onTrigger) {
                HStack(spacing: Theme.Space.tight) {
                    Image(systemName: isActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isActive ? Theme.accent : Color.secondary)
                        .frame(width: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.name)
                            .font(Theme.Font.body)
                            .fontWeight(isActive ? .semibold : .regular)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let summary {
                            Text(summary)
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isActive ? "Turn off \(preset.name)" : "Run \(preset.name)")

            KeyboardShortcuts.Recorder(for: .preset(id: preset.id)) { newValue in
                guard let newValue,
                      let collision = ShortcutRegistry.findCollision(
                          proposed: newValue,
                          excluding: .preset(id: preset.id),
                          candidates: allShortcutNames
                      )
                else { return }
                // The editor blocks Save on a collision before anything is
                // ever written; the row records live, so the only way to
                // "block" here is to undo what was just typed and say why.
                KeyboardShortcuts.setShortcut(nil, for: .preset(id: preset.id))
                onCollision(collision)
            }
            .controlSize(.small)

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
        }
        .padding(.horizontal, Theme.Space.tight)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.controlRadius, style: .continuous)
                // A tint rather than a solid accent fill. A full-width slab
                // of accent would outweigh the speed and mode controls above
                // it, and the row is a peer of those, not their headline.
                // Tint plus an accent icon plus a heavier name says active
                // without spending the loudest colour in the app on it.
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
