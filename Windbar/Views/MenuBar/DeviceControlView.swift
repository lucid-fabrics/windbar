import AppKit
import KeyboardShortcuts
import SwiftUI

/// Renders one device from its `controlsConf`, rather than hardcoding
/// behaviour per model. Speed, Mode and Oscillation get purpose-built
/// controls; any other section with selectable values falls back to a chip
/// row, so an unfamiliar product still gets something usable.
struct DeviceControlView: View {
    let appModel: AppModel
    let device: DreoDevice
    /// Accordion state, owned by `MenuBarView` since only it can know which
    /// other cards must close. False only when this is the sole fan, where
    /// there is nothing to take turns with.
    var isCollapsible = false
    var isExpanded = true
    var onToggleExpanded: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @State private var showsPreferences = false
    /// Non-nil while the preset editor has taken over the card. Held here
    /// rather than in the presets section so the editor can replace the
    /// whole card instead of nesting a panel inside it.
    @State private var presetEditing: PresetEditor.Mode?

    private var sections: [ControlSection] { device.controlsConf?.control ?? [] }
    private var presets: [DevicePreset] {
        appModel.settings.presetsBySerialNumber[device.serialNumber] ?? []
    }
    private var preferences: [ControlSection] {
        (device.controlsConf?.preference ?? []).filter { $0.cmd != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.roomy) {
            if let mode = presetEditing, isExpanded {
                editor(for: mode)
            } else {
                cardContent
            }
        }
        .padding(Theme.Metric.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .fill(cardFill)
        )
        .opacity(cardOpacity)
        // An editor left open on a card that gets collapsed would otherwise
        // still be there, mid-edit, whenever the card is expanded again,
        // which is not what closing something looks like.
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { presetEditing = nil }
        }
        .animation(.easeOut(duration: 0.18), value: device.isOn)
        .animation(.easeOut(duration: 0.18), value: device.isOnline)
        .animation(.snappy(duration: 0.2), value: presetEditing == nil)
        // Kept out of the card body so a destructive action can't be hit by
        // mistake while reaching for a speed or mode control.
        .contextMenu {
            Button("Remove \(device.deviceName)…", role: .destructive, action: confirmRemoval)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        header

        if isExpanded {
            expandedContent
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if !device.isOnline {
            Text("This device is offline. Check it has power and is in range of your WiFi.")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.roomy) {
                if sections.isEmpty {
                    Text("No controls published for this model. Power still works.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(sections) { section in
                    sectionView(for: section)
                }
                // Unconditional now that the built-in Power row means the
                // list is never empty. It used to appear only once a preset
                // existed, which left the power shortcut discoverable solely
                // by opening More options and finding it there.
                ShortcutsSection(
                    appModel: appModel,
                    device: device,
                    presets: presets,
                    onEdit: { presetEditing = .edit($0) }
                )
                preferencesSection
            }
            // Nothing sent to an unreachable device can take effect, so
            // its controls stop accepting input rather than silently
            // dropping commands. The header stays live so an offline
            // device can still be managed and removed.
            .disabled(!device.isOnline)
        }
    }

    /// Puts this device's trigger URL on the clipboard.
    ///
    /// Macro keys never arrive as keystrokes, so a G-key or Stream Deck button
    /// cannot be recorded as a shortcut. They can all open a URL though, which
    /// is how they aim at this specific fan.
    private func copyTriggerLink() {
        let link = "windbar://toggle?device=\(device.serialNumber)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    /// Runs as a real modal alert rather than a SwiftUI confirmation dialog.
    /// The menu bar popover closes as soon as it loses focus, and a dialog
    /// presented from inside it goes with it, so the confirmation vanished
    /// the moment it was clicked. A window-level alert outlives the popover
    /// and stays put until one of its buttons is chosen.
    private func confirmRemoval() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(device.deviceName)?"
        alert.informativeText = "This unlinks the fan from your Dreo account everywhere, not just on "
            + "this Mac. To use it again you would have to pair it from scratch."
        alert.addButton(withTitle: "Remove Device")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        // Return picks Cancel, so leaning on the keyboard cannot delete a
        // device by accident.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await appModel.removeDevice(device) }
    }

    // MARK: - Header

    private var cardOpacity: Double {
        // The editor is the focused thing on screen while it is open, so it
        // never inherits the dimming that says "this fan is off".
        if presetEditing != nil { return 1 }
        // A collapsed row is one line carrying the only state that fan is
        // showing at all. Dimming it the way a full card can afford to be
        // dimmed would make the fans you are not currently adjusting the
        // hardest ones to read, which is backwards.
        if !isExpanded { return device.isOnline ? 1 : 0.7 }
        if !device.isOnline { return 0.55 }
        return device.isOn ? 1 : 0.72
    }

    /// Editing washes the whole card towards the accent. Filled, never a
    /// border: the surface is what carries the state, same rule as the rest
    /// of the app.
    private var cardFill: Color {
        presetEditing == nil ? Theme.surface(scheme) : Theme.accentWash(scheme)
    }

    private var iconTint: Color {
        guard device.isOnline else { return .secondary }
        return device.isOn ? Theme.accent : .secondary
    }

    private var header: some View {
        DeviceHeaderView(
            device: device,
            isCollapsible: isCollapsible,
            isExpanded: isExpanded,
            onToggleExpanded: onToggleExpanded,
            onCopyTriggerLink: copyTriggerLink,
            onCopyDeviceReport: copyDeviceReport,
            onRemove: confirmRemoval,
            onTogglePower: { appModel.togglePower(for: device) }
        )
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Button {
                showsPreferences.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(showsPreferences ? "Fewer options" : "More options")
                        .font(Theme.Font.sectionLabel)
                        .tracking(0.7)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(showsPreferences ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsPreferences {
                VStack(spacing: Theme.Space.snug) {
                    ForEach(preferences) { preference in
                        ToggleRow(
                            title: sectionTitle(preference),
                            isOn: Binding(
                                get: { isPreferenceOn(preference) },
                                set: { setPreference(preference, to: $0) }
                            )
                        )
                    }

                    // A device whose schema has no sections has nothing a
                    // preset could capture. Offering the row anyway just
                    // hands the user an editor whose Save button can never
                    // turn on: the "No controls published" message above
                    // already says everything there is to say about it.
                    if !sections.isEmpty {
                        if presets.isEmpty {
                            Text("A preset saves how the fan blows behind one name and "
                                 + "shortcut. Running it turns the fan on, running it "
                                 + "again turns the fan off.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HoverRow(icon: "plus.circle", title: "New Preset…") {
                            presetEditing = .create
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: showsPreferences)
    }

    /// Some preferences read inverted (`muteon` is true when panel sound is
    /// off) and some use ints instead of booleans, so both are normalised
    /// to what the label actually claims.
    func isPreferenceOn(_ section: ControlSection) -> Bool {
        guard let cmd = section.cmd, let raw = device.state[cmd] else { return false }
        let enabled = section.trueValue.map { raw == $0 } ?? (raw.boolValue ?? false)
        return (section.reverse ?? false) ? !enabled : enabled
    }

    func setPreference(_ section: ControlSection, to newValue: Bool) {
        guard let cmd = section.cmd else { return }
        let target = (section.reverse ?? false) ? !newValue : newValue
        let value: DreoValue
        if let onValue = section.trueValue, let offValue = section.falseValue {
            value = target ? onValue : offValue
        } else {
            value = .bool(target)
        }
        appModel.setValue(value, forKey: cmd, on: device)
    }

    func sectionTitle(_ section: ControlSection) -> String {
        (section.title ?? section.type).dreoTitleCased
    }
}

// MARK: - Reporting

private extension DeviceControlView {
    /// For reporting a fan with buttons this app has no controls for. The
    /// serial is left out on purpose: reports get pasted in public, and the
    /// model plus the unshown keys is everything needed to add the control.
    func copyDeviceReport() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            DeviceDiagnostics.report(for: device, appVersion: version),
            forType: .string
        )
    }
}

// MARK: - Preset editing

private extension DeviceControlView {
    func editor(for mode: PresetEditor.Mode) -> some View {
        PresetEditor(
            device: device,
            mode: mode,
            takenNames: takenNames(for: mode),
            allShortcutNames: ShortcutRegistry.names(
                devices: appModel.devices,
                presetsBySerialNumber: appModel.settings.presetsBySerialNumber
            ),
            onSave: { saved in
                appModel.savePreset(saved, on: device)
                presetEditing = nil
            },
            onCancel: { presetEditing = nil }
        )
        // Explicit identity, so switching from creating to editing (or to a
        // different preset) starts the editor fresh instead of inheriting the
        // previous target's id, name and values from SwiftUI's state store.
        .id(editorIdentity(for: mode))
        .transition(.opacity)
    }

    func editorIdentity(for mode: PresetEditor.Mode) -> String {
        switch mode {
        case .create: return "new"
        case .edit(let preset): return preset.id.uuidString
        }
    }

    func takenNames(for mode: PresetEditor.Mode) -> [String] {
        switch mode {
        case .create: return presets.map(\.name)
        case .edit(let preset): return presets.filter { $0.id != preset.id }.map(\.name)
        }
    }
}
