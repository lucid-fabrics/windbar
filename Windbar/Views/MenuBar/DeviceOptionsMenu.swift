import SwiftUI

/// Per-device actions behind a visible button. A right-click only menu is
/// undiscoverable: nothing on screen advertises that it exists.
struct DeviceOptionsMenu: View {
    let deviceName: String
    let onCopyTriggerLink: () -> Void
    let onCopyDeviceReport: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button("Copy Trigger Link", action: onCopyTriggerLink)
            // For reporting a fan whose buttons this app has no controls for.
            // Carries the model and the keys the fan publishes that nothing
            // renders, which is what adding those controls needs.
            Button("Copy Device Report", action: onCopyDeviceReport)
            Divider()
            Button("Remove Device…", role: .destructive, action: onRemove)
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
        .help("Device options")
        .accessibilityLabel("Options for \(deviceName)")
    }
}

extension String {
    /// Schemas from the server carry raw localisation keys such as
    /// `device_control_mode_sleep`, while the bundled templates already hold
    /// English. Keys are looked up in the vendor's own string table first, so
    /// labels read the way the Dreo app words them, and anything unknown falls
    /// back to tidying the key itself.
    var dreoTitleCased: String {
        if let label = DeviceLabels.text(forKey: self) { return label }
        guard contains("_") else { return self }
        var words = split(separator: "_").map(String.init)
            .filter { !["device", "control", "fans", "base"].contains($0.lowercased()) }
        if words.count > 1, words.first?.lowercased() == "mode" {
            words.removeFirst()
        }
        if words.isEmpty { words = [self] }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
