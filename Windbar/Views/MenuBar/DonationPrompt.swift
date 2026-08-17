#if WINDBAR_DONATIONS
import SwiftUI

/// The donation ask, direct-download build only. Absent from the App Store build.
///
/// Deliberately quiet on TIMING: it sits inside the popover the user already
/// opened rather than stealing focus with a window, it never blocks a control,
/// and one click closes it. `DonationCoordinator` means most people see this once
/// after four months of real use, if ever, at most three times in the app's life.
///
/// It is deliberately NOT quiet on PRESENCE: the gating already does the work of
/// not annoying anyone, so the card itself is allowed to look considered rather
/// than apologise for existing. A badge, elevation and a spring entrance instead
/// of a flat inline row.
struct DonationPrompt: View {
    let coordinator: DonationCoordinator

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let pitch = coordinator.pitch {
            content(pitch)
        }
    }

    private func content(_ pitch: DonationPitch) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            header(pitch)
            amountButtons
            if pitch.allowsOptOut {
                Button("No thanks") { withAnimation { coordinator.optOut() } }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 14, y: 6)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
            removal: .opacity))
    }

    private func header(_ pitch: DonationPitch) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.tight) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                Text(pitch.headline)
                    .font(.system(size: 13.5, weight: .bold))
                Text(pitch.body)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // The stats change every render; animate them in rather than
                    // have a number just appear mid-sentence.
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { coordinator.dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    private var amountButtons: some View {
        HStack(spacing: Theme.Space.tight) {
            ForEach(Donations.links, id: \.label) { link in
                Button {
                    if let url = URL(string: link.url) { openURL(url) }
                    // Records rather than just closes, so this is the last
                    // time the app brings it up on its own.
                    withAnimation { coordinator.recordDonation() }
                } label: {
                    Text(link.label)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .fill(.regularMaterial)
            // A hairline instead of a border: an accent-coloured ring on a rounded
            // card is the one look this app's own design rules forbid.
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
        }
    }

    /// A soft accent badge rather than a literal heart or dollar glyph: it reads
    /// as "from the app" without over-committing to any one metaphor.
    private var badge: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Theme.accent.opacity(0.95), Theme.accent.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: "fan.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
            )
    }
}
#endif
