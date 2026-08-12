import SwiftUI

/// First-launch onboarding. Walks the user through a short, focused sequence
/// before they sign in: clear the value, hand off to the real login, then
/// ride them straight to pairing. The flow auto-skips itself once a device
/// has been paired at least once, so returning users never see it again.
struct OnboardingView: View {
    let appModel: AppModel
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome = 0
        case signIn
        case addDevice
        case done
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    private var authState: AppModel.LaunchState { appModel.launchState }
    private var hasDevices: Bool { !appModel.devices.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if step == .welcome {
                WelcomeScreen(advance: advance)
            } else {
                progressHeader
                    .padding(.top, Theme.Space.roomy)
                    .padding(.horizontal, Theme.Space.loose + 2)
                content(for: step)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(.bottom, Theme.Space.loose + 2)
        .onChange(of: authState) { _, newValue in
            if step == .signIn, newValue == .ready {
                advance(to: hasDevices ? .done : .addDevice)
            }
        }
        .onChange(of: hasDevices) { _, hasAny in
            if step == .addDevice, hasAny {
                advance(to: .done)
            }
        }
    }

    private var progressHeader: some View {
        let total = Step.allCases.count - 1
        return HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { index in
                let active = index <= step.rawValue
                Capsule()
                    .fill(active ? Theme.accent : Theme.hairline(scheme))
                    .frame(height: 3)
            }
        }
    }

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .welcome:
            Color.clear
        case .signIn:
            LoginView(appModel: appModel)
                .padding(.top, Theme.Space.tight)
        case .addDevice:
            addDeviceStep
                .padding(.horizontal, Theme.Space.loose + 2)
                .padding(.top, Theme.Space.snug)
        case .done:
            done
                .padding(.horizontal, Theme.Space.loose + 2)
                .padding(.top, Theme.Space.snug)
        }
    }

    private var addDeviceStep: some View {
        VStack(spacing: Theme.Space.roomy) {
            Spacer().frame(height: 4)

            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: "fan.badge.plus")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 4) {
                Text("Pair your fan")
                    .font(.system(size: 15, weight: .semibold))
                Text("Windbar needs the fan to be in pairing mode. Hold the pairing button until the LED blinks.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer().frame(height: 2)

            Button("Open Pairing Window") {
                appModel.hasRequestedPairing = true
                openWindow(id: "add-device")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 220)
    }

    private var done: some View {
        VStack(spacing: Theme.Space.roomy) {
            Spacer().frame(height: 12)

            ZStack {
                Circle()
                    .fill(Theme.success.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.success)
            }

            VStack(spacing: 4) {
                Text("All set")
                    .font(.system(size: 17, weight: .semibold))
                Text("Windbar is ready. Click the menu bar icon any time to control your fan.")
                    .font(Theme.Font.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Done") {
                finish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 220)
    }

    private func advance() {
        let next = Step(rawValue: step.rawValue + 1)
        advance(to: next)
    }

    private func advance(to next: Step?) {
        guard let next else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            step = next
        }
    }

    private func finish() {
        appModel.settings.hasCompletedOnboarding = true
    }
}

// MARK: - Welcome screen

/// Atmospheric first screen: gradient sky, breathing ring hero, three feature
/// rows, single primary CTA. Sized slightly wider than the rest of the flow
/// so the gradient has room to breathe.
private struct WelcomeScreen: View {
    let advance: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(spacing: Theme.Space.snug) {
                Text("Welcome to Windbar")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Control your Dreo fans without opening the Dreo app.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.loose + 2)
            .padding(.top, Theme.Space.roomy + 2)

            features
                .padding(.top, Theme.Space.roomy + 2)
                .padding(.horizontal, Theme.Space.loose + 2)

            Spacer(minLength: Theme.Space.roomy)

            VStack(spacing: Theme.Space.tight) {
                Button(action: advance) {
                    Text("Get Started")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.loose + 2)
            .padding(.bottom, Theme.Space.snug)
        }
        .frame(width: Theme.Metric.popoverWidth + 16)
        .background(welcomeBackground)
    }

    /// Sky-tinted gradient. The accent at the top fading to a near-clear
    /// surface at the bottom is what gives the screen atmosphere without
    /// needing an image asset.
    private var welcomeBackground: some View {
        LinearGradient(
            colors: [
                Theme.accent.opacity(0.22),
                Theme.accent.opacity(0.10),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    /// Three concentric layers: a stroke ring, a tinted disc, a gradient
    /// core, and the glyph. Fully static. No motion on this layer so the
    /// screen feels calm; the only animation in the flow is the step
    /// transition between screens.
    private var hero: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.30), lineWidth: 1)
                .frame(width: 130, height: 130)
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 96, height: 96)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 76, height: 76)
            Image(systemName: "wind")
                .font(.system(size: 36, weight: .light, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
        .frame(height: 130)
        .padding(.top, Theme.Space.roomy + 4)
    }

    private var features: some View {
        VStack(spacing: Theme.Space.tight + 2) {
            FeatureRow(icon: "fan.fill", title: "Full fan control",
                       subtitle: "Power, speed, mode, oscillation, lights")
            FeatureRow(icon: "bolt.fill", title: "Live socket",
                       subtitle: "Changes apply in under a second")
            FeatureRow(icon: "keyboard", title: "Global hotkey",
                       subtitle: "Toggle your last fan from anywhere")
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.snug) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.10))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingView(appModel: AppModel())
        .frame(width: 320, height: 460)
}
