import AppKit
import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel

    @Environment(\.openSettings) private var openSettings
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

            HoverRow(icon: "power", title: "Quit Windbar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.Space.tight)
    }
}
