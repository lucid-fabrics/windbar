import SwiftUI

/// The per-control renderers for a device card. The device's own schema picks
/// which one each section gets, so an unfamiliar product still gets something
/// usable rather than nothing.
extension DeviceControlView {
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
            // A switch that governs the controls under it, e.g. the light
            // ring's own power. Preferences render these too, but this one
            // has to sit with what it governs.
            ToggleRow(
                title: sectionTitle(section),
                isOn: Binding(
                    get: { isPreferenceOn(section) },
                    set: { setPreference(section, to: $0) }
                )
            )
        default:
            chipSection(for: section)
        }
    }

    @ViewBuilder
    func speedControl(for section: ControlSection) -> some View {
        if let items = section.items, items.count >= 2,
           let low = items.map(\.value).compactMap(\.intValue).min(),
           let high = items.map(\.value).compactMap(\.intValue).max(),
           low < high, let cmd = items.first?.cmd {
            let current = min(max(device.state[cmd]?.intValue ?? low, low), high)
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(title: sectionTitle(section), trailing: "\(current)")
                StepSlider(range: low...high, value: current) { step in
                    appModel.setValue(.int(step), forKey: cmd, on: device)
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
                        get: { device.state[cmd]?.boolValue ?? false },
                        set: { appModel.setValue(.bool($0), forKey: cmd, on: device) }
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
        let selected = items.first { device.state[$0.cmd] == $0.value }?.id
        return SegmentedChips(
            items: items,
            selection: selected,
            label: { $0.text.dreoTitleCased },
            action: { appModel.setValue($0.value, forKey: $0.cmd, on: device) }
        )
    }

    @ViewBuilder
    func colorControl(for section: ControlSection) -> some View {
        if let items = section.items, !items.isEmpty, let cmd = items.first?.cmd {
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                SectionLabel(title: sectionTitle(section))
                ColorSwatches(
                    items: items,
                    selection: device.state[cmd]?.intValue,
                    action: { appModel.setValue($0.value, forKey: $0.cmd, on: device) }
                )
            }
        }
    }
}
