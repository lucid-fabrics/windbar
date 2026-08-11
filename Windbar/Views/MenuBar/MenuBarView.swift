import AppKit
import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel

    @Environment(\.openSettings) private var openSettings
    @State private var isConfirmingSignOut = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch appModel.launchState {
            case .loading:
                StatusPlaceholder(isBusy: true, message: "Connecting to your devices…")
            case .needsLogin:
                if appModel.settings.hasCompletedOnboarding {
                    LoginView(appModel: appModel)
                } else {
                    OnboardingView(appModel: appModel)
                }
            case .ready:
                ready
            }
        }
        .frame(width: Theme.Metric.popoverWidth)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            if appModel.devices.isEmpty {
                StatusPlaceholder(
                    systemImage: "fan.slash",
                    message: "No Dreo devices on this account yet."
                )
            } else {
                VStack(spacing: Theme.Space.snug) {
                    ForEach(appModel.devices) { device in
                        DeviceControlView(appModel: appModel, device: device)
                    }
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, Theme.Metric.gutter)
            }

            if let errorMessage = appModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
                    .padding(.horizontal, Theme.Metric.gutter)
            }

            #if WINDBAR_DONATIONS
            if appModel.donations.isShowing {
                DonationPrompt(coordinator: appModel.donations)
                    .padding(.horizontal, Theme.Metric.gutter)
                    .transition(.opacity)
            }
            #endif

            Divider()
                .padding(.horizontal, Theme.Metric.gutter)

            footer
        }
        .padding(.bottom, Theme.Space.snug)
        #if WINDBAR_DONATIONS
        .onAppear { appModel.donations.popoverDidOpen() }
        .animation(.easeInOut(duration: 0.18), value: appModel.donations.isShowing)
        #endif
    }

    private var footer: some View {
        VStack(spacing: 1) {
            HoverRow(
                icon: "arrow.clockwise",
                title: "Refresh Devices",
                isLoading: appModel.isRefreshingDevices
            ) {
                Task { await appModel.refreshDevices() }
            }
            .keyboardShortcut("r")

            HoverRow(icon: "plus.circle", title: "Add a Device…") {
                appModel.hasRequestedPairing = true
                // Order matters: activating before the window exists leaves
                // it behind whatever app was frontmost.
                openWindow(id: "add-device")
                NSApp.activate(ignoringOtherApps: true)
            }

            HoverRow(icon: "gearshape", title: "Preferences…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            #if WINDBAR_DONATIONS
            // Always here, independent of the earned-ask gating below: a
            // misclicked "No thanks" or a change of heart six months after
            // opting out should not be a locked door. This never triggers
            // itself, so it is not a second nag, just a door that stays open.
            HoverRow(icon: "heart", title: "Support Windbar…") {
                withAnimation { appModel.donations.showManually() }
            }
            #endif

            // Account actions also live in Preferences, but this popover is the
            // whole app: anything only reachable one window deeper is, in
            // practice, not reachable.
            if isConfirmingSignOut {
                signOutConfirmation
            } else {
                HoverRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out…") {
                    isConfirmingSignOut = true
                }
            }

            HoverRow(icon: "power", title: "Quit Windbar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.Space.tight)
        .animation(.easeInOut(duration: 0.15), value: isConfirmingSignOut)
    }

    /// Confirmation drawn INSIDE the popover, on purpose.
    ///
    /// `.confirmationDialog` and `.alert` cannot be used from a MenuBarExtra window:
    /// presenting one makes the popover resign key, macOS dismisses the popover, and
    /// the dialog goes with it before any button can be pressed. Anything that must
    /// be confirmed here has to be confirmed in place.
    private var signOutConfirmation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            Text("Sign out of Dreo?")
                .font(Theme.Font.deviceName)
            Text("Your password will be removed from the Keychain. Your fans "
                 + "disappear until you sign in again.")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.tight) {
                Button("Cancel") { isConfirmingSignOut = false }
                    .controlSize(.small)
                Button("Sign Out", role: .destructive) {
                    isConfirmingSignOut = false
                    Task { await appModel.signOut() }
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.controlRadius, style: .continuous)
                .fill(Theme.surface(colorScheme))
        )
    }
}
