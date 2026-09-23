import SwiftUI

/// What to do to the physical fan before pairing can start. Shown first and
/// left on screen until the person says the fan is ready, because the fan
/// only advertises for a short window after the button press.
struct PairingInstructions: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.roomy) {
            Text("Put the fan into pairing mode first, then this Mac can set it up over Bluetooth. "
                 + "No phone needed.")
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                step(1, "Plug the fan in and switch it on.")
                // The button differs by model and the model is unknown until
                // pairing finishes, so name both rather than guess one.
                step(2, "Hold the pairing button for about 5 seconds. On most Dreo fans "
                     + "that is Oscillation; some have a WiFi button instead.")
                step(3, "Wait for the WiFi light to start blinking.")
                step(4, "Keep the fan within a few metres of this Mac.")
            }

            // The most common reason pairing fails, so it gets a filled,
            // readable callout rather than a faint footnote.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
                Image(systemName: "wifi")
                    .foregroundStyle(Theme.accent)
                Text("Fans join 2.4 GHz networks only, so have that network's password handy.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Font.body)
            .padding(Theme.Space.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.controlRadius, style: .continuous)
                    .fill(Theme.accentTint(scheme))
            )
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.snug) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
            Text(text)
                .font(Theme.Font.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The networks the fan itself can see, strongest first. Showing the fan's
/// own view rather than the Mac's matters: the fan may sit somewhere with
/// very different reception.
struct NetworkPicker: View {
    let networks: [DiscoveredWiFiNetwork]
    let onSelect: (DiscoveredWiFiNetwork) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            if networks.isEmpty {
                StatusPlaceholder(
                    systemImage: "wifi.exclamationmark",
                    message: "The fan didn't report any networks it can see. Move it closer to your "
                        + "router and scan again."
                )
            } else {
                Text("These are the networks your fan can see, strongest first.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(networks) { network in
                            HoverRow(icon: Self.signalIcon(for: network.rssi), title: network.ssid) {
                                onSelect(network)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
    }

    static func signalIcon(for rssi: Int) -> String {
        switch rssi {
        case (-60)...: "wifi"
        case (-75)..<(-60): "wifi.exclamationmark"
        default: "wifi.slash"
        }
    }
}

struct PairingSuccess: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            HStack(spacing: Theme.Space.snug) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.success)
                Text("Your fan is on WiFi and linked to your account.")
                    .font(Theme.Font.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("It should appear in the menu bar in a moment. If it doesn't, choose Refresh Devices.")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
