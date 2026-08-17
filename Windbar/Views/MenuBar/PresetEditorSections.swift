import SwiftUI

// MARK: - Controls

/// Same rendering rules as `DeviceControlView`, but reading and writing the
/// draft dictionary instead of the live device. Split into its own file to
/// keep PresetEditor.swift under the project's file-length budget; internal
/// rather than private, since `body` in that file calls `controls`.
extension PresetEditor {
    var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            ForEach(device.controlsConf?.control ?? []) { section in
                sectionView(for: section)
            }
        }
    }

    @ViewBuilder
    func sectionView(for section: ControlSection) -> some View {
        switch section.type {
        case "Speed":
            speedControl(for: section)
        case "Oscillation":
            oscillationControl(for: section)
        case "Color":
            colorControl(for: section)
        case "Toggle":
            toggleControl(for: section)
        default:
            chipSection(for: section)
        }
    }

    /// A switch inside the shape being edited, e.g. the light's own on/off.
    ///
    /// Without this case the editor fell through to the chip-row default,
    /// which needs `items` and a Toggle section has none, so it silently
    /// rendered nothing. `seed()` still captures the switch's value into the
    /// draft either way, so a preset saved while this was missing could hold
    /// the light off underneath colours and brightness the user had visibly
    /// set and thought they were saving lit.
    @ViewBuilder
    func toggleControl(for section: ControlSection) -> some View {
        if section.cmd != nil {
            ToggleRow(
                title: sectionTitle(section),
                isOn: Binding(
                    get: { isDraftPreferenceOn(section) },
                    set: { setDraftPreference(section, to: $0) }
                )
            )
        }
    }

    /// Mirrors `DeviceControlView.isPreferenceOn`/`setPreference`, reading and
    /// writing the draft `values` dict instead of the live device, so a
    /// switch with inverted or non-boolean semantics (`reverse`, `trueValue`/
    /// `falseValue`) behaves the same in the editor as it does on the card.
    func isDraftPreferenceOn(_ section: ControlSection) -> Bool {
        guard let cmd = section.cmd, let raw = values[cmd] else { return false }
        let enabled = section.trueValue.map { raw == $0 } ?? (raw.boolValue ?? false)
        return (section.reverse ?? false) ? !enabled : enabled
    }

    func setDraftPreference(_ section: ControlSection, to newValue: Bool) {
        guard let cmd = section.cmd else { return }
        let target = (section.reverse ?? false) ? !newValue : newValue
        if let onValue = section.trueValue, let offValue = section.falseValue {
            values[cmd] = target ? onValue : offValue
        } else {
            values[cmd] = .bool(target)
        }
    }

    @ViewBuilder
    func colorControl(for section: ControlSection) -> some View {
        if let items = section.items, !items.isEmpty, let cmd = items.first?.cmd {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(title: sectionTitle(section))
                ColorSwatches(
                    items: items,
                    selection: values[cmd]?.intValue,
                    action: { values[$0.cmd] = $0.value }
                )
            }
        }
    }

    @ViewBuilder
    func speedControl(for section: ControlSection) -> some View {
        if let items = section.items, items.count >= 2,
           let low = items.map(\.value).compactMap(\.intValue).min(),
           let high = items.map(\.value).compactMap(\.intValue).max(),
           low < high, let cmd = items.first?.cmd {
            let current = min(max(values[cmd]?.intValue ?? low, low), high)
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(title: sectionTitle(section), trailing: "\(current)")
                StepSlider(range: low...high, value: current) { step in
                    values[cmd] = .int(step)
                }
            }
        }
    }

    @ViewBuilder
    func oscillationControl(for section: ControlSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(spacing: Theme.Space.tight) {
                SectionLabel(title: sectionTitle(section))
                if let cmd = section.cmd {
                    Toggle("", isOn: Binding(
                        get: { values[cmd]?.boolValue ?? false },
                        set: { values[cmd] = .bool($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
            if let items = section.items, !items.isEmpty {
                chipRow(items: items)
            }
        }
    }

    @ViewBuilder
    func chipSection(for section: ControlSection) -> some View {
        if let items = section.items, !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(title: sectionTitle(section))
                chipRow(items: items)
            }
        }
    }

    func chipRow(items: [ControlItem]) -> some View {
        let selected = items.first { values[$0.cmd] == $0.value }?.id
        return SegmentedChips(
            items: items,
            selection: selected,
            label: { $0.text.dreoTitleCased },
            action: { values[$0.cmd] = $0.value }
        )
    }

    func sectionTitle(_ section: ControlSection) -> String {
        (section.title ?? section.type).dreoTitleCased
    }
}
