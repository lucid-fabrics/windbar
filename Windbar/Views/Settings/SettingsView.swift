import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let appModel: AppModel

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isConfirmingSignOut = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Label("Startup", systemImage: "power")
            }

            #if DEBUG && WINDBAR_DONATIONS
            donationPreview
            #endif

            Section {
                Button("Sign Out…", role: .destructive) { isConfirmingSignOut = true }
                    .disabled(appModel.launchState != .ready)
            } header: {
                Label("Account", systemImage: "person.crop.circle")
            } footer: {
                Text("Removes your Dreo password from the macOS Keychain and disconnects. "
                     + "You will need to sign in again to control your fans.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        #if DEBUG && WINDBAR_DONATIONS
        .frame(width: 400, height: 360)
        #else
        .frame(width: 400, height: 200)
        #endif
        // Confirm first: this discards a password the user may not remember, and there
        // is no undo.
        .confirmationDialog("Sign out of Dreo?", isPresented: $isConfirmingSignOut) {
            Button("Sign Out", role: .destructive) {
                Task { await appModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your password will be removed from the Keychain and your fans will "
                 + "disappear from the menu bar until you sign in again.")
        }
    }

    #if DEBUG && WINDBAR_DONATIONS
    /// Local preview of the direct-download build's donation card.
    ///
    /// Present only in a Debug build of the direct-download configuration, so
    /// it cannot reach either shipping BINARY: both `release` and `release_dmg`
    /// build Release, and `release` additionally proves no donation code is in
    /// the archive before uploading. Store screenshots are a separate risk
    /// with its own separate guard: see the comment on the Debug config in
    /// project.yml and the canary in ScreenshotHarness.swift.
    ///
    /// Reaching the real card takes 14 days, 50 toggles and 7 separate days of
    /// use, which is correct for users and impossible to work against. These
    /// show the card without spending a real ask.
    @ViewBuilder
    private var donationPreview: some View {
        Section {
            Button("Show Next Ask") { appModel.donations.debugShowAsk() }
            Button("Show First Ask") { appModel.donations.debugShowAsk(index: 0) }
            Button("Show Second Ask") { appModel.donations.debugShowAsk(index: 1) }
            Button("Show Final Ask") { appModel.donations.debugShowAsk(index: 2) }
            Divider()
            Button("Mark as Donated") { appModel.donations.debugMarkDonated() }
            Button("Reset Donation State", role: .destructive) { appModel.donations.debugReset() }
        } header: {
            Label("Donations (debug)", systemImage: "hammer")
        } footer: {
            Text(appModel.donations.debugSummary + "\n"
                 + "Open the menu bar popover to see the card. Debug builds only, "
                 + "never present in a release.")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
