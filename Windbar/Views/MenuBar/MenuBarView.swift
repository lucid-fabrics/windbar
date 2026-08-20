import AppKit
import SwiftUI

struct MenuBarView: View {
    let appModel: AppModel

    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    /// Which fan is showing its full card. One at a time, because a device
    /// card is roughly a third of the screen height and two of them already
    /// fill a laptop display, so a fourth fan would mean scrolling a menu bar
    /// popover to reach a power switch. Held here rather than in each card
    /// since expanding one has to close the others.
    @State private var expansion: Expansion = .unchosen

    /// `unchosen` is deliberately distinct from `allCollapsed`. Resolving the
    /// default during the first render rather than in `onAppear` is what
    /// keeps the popover from drawing every card shut for one frame and then
    /// snapping one open, and it lets collapsing the last open card stay a
    /// real state instead of being immediately undone by the default.
    private enum Expansion: Equatable {
        case unchosen
        case allCollapsed
        case device(String)
    }

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
                        DeviceControlView(
                            appModel: appModel,
                            device: device,
                            isCollapsible: isAccordion,
                            isExpanded: isExpanded(device),
                            onToggleExpanded: { toggleExpansion(device) }
                        )
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

    // MARK: - Accordion

    /// One fan needs no accordion: there is nothing to take turns with, and a
    /// disclosure chevron on a card that can never collapse is a control that
    /// does nothing. The behaviour appears exactly when the problem does.
    private var isAccordion: Bool { appModel.devices.count > 1 }

    private func isExpanded(_ device: DreoDevice) -> Bool {
        guard isAccordion else { return true }
        switch expansion {
        case .unchosen:
            return device.serialNumber == defaultExpandedSerialNumber
        case .allCollapsed:
            return false
        case .device(let chosen):
            // A chosen fan that has since been removed, or that belonged to a
            // previous account, would otherwise leave every card shut with
            // nothing on screen explaining why.
            guard appModel.devices.contains(where: { $0.serialNumber == chosen }) else {
                return device.serialNumber == defaultExpandedSerialNumber
            }
            return device.serialNumber == chosen
        }
    }

    /// Deliberately unanimated. `MenuBarExtra(.window)` sizes its panel to
    /// fit the content and re-anchors it to the menu bar item on every step,
    /// so animating the height underneath it makes the whole popover shudder
    /// for as long as the animation runs. Snapping resizes the window once,
    /// in the same frame the content changes, which is what a menu does
    /// anyway. The chevron still animates, since rotation costs no height.
    private func toggleExpansion(_ device: DreoDevice) {
        expansion = isExpanded(device) ? .allCollapsed : .device(device.serialNumber)
    }

    /// Opens on the fan you last touched.
    ///
    /// `lastSelectedDeviceSerialNumber` is already what a device-less URL
    /// trigger aims at, so expanding the same one makes "the
    /// fan Windbar is currently about" a single idea rather than two that
    /// happen to usually agree.
    private var defaultExpandedSerialNumber: String? {
        let lastUsed = appModel.settings.lastSelectedDeviceSerialNumber
        return appModel.devices.first { $0.serialNumber == lastUsed }?.serialNumber
            ?? appModel.devices.first?.serialNumber
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

            #if WINDBAR_DIRECT
            // Direct-download build only: the App Store updates its own copy,
            // and shipping a second way to do it there is a rejection. This
            // is for anyone who would rather look than wait for the scheduled
            // check; Sparkle owns everything after the click, including the
            // release notes, the download and the restart.
            HoverRow(icon: "arrow.down.circle", title: "Check for Updates…") {
                NSApp.activate(ignoringOtherApps: true)
                appModel.updates.checkForUpdates()
            }
            #endif

            #if WINDBAR_DONATIONS
            // Always here, independent of the earned-ask gating below: a
            // misclicked "No thanks" or a change of heart six months after
            // opting out should not be a locked door. This never triggers
            // itself, so it is not a second nag, just a door that stays open.
            //
            // For someone who has given, the filled heart is the whole
            // acknowledgement. Quiet enough to miss, there every time if you
            // look, and it never says anything about them to anyone else.
            HoverRow(
                icon: appModel.donations.hasDonated ? "heart.fill" : "heart",
                title: "Support Windbar…"
            ) {
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
