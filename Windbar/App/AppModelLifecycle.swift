import Foundation
import os

/// Login, device loading and the update-stream subscription. Split out of
/// AppModel.swift to keep the primary type declaration under the project's
/// type-body-length budget; internal rather than private, since `start()`
/// and the `settings` `didSet` in AppModel.swift call into this file.
extension AppModel {
    func login(credentials: DreoCredentials, persist: Bool) async {
        errorMessage = nil
        do {
            try await apiService.login(credentials)
            if persist {
                try? await keychainRepository.save(credentials)
            }
            try await loadDevicesAndConnect()
            launchState = .ready
        } catch {
            Self.logger.warning("Login failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't sign in. Check your email and password."
            launchState = .needsLogin
        }
    }

    func loadDevicesAndConnect() async throws {
        try await loadDevices()

        if let session = await apiService.currentSession() {
            await socketService.connect(session: session)
            subscribeToUpdates()
        }
    }

    func loadDevices() async throws {
        var loaded = try await apiService.listDevices()
        for index in loaded.indices {
            if let state = try? await apiService.fetchState(for: loaded[index].serialNumber) {
                loaded[index].apply(state)
            }
        }
        devices = loaded
        for device in loaded {
            wireState[device.serialNumber] = device.state
        }
        // Names only, never values: this lands in the system log, and a key
        // list is all that is needed to spot a control the bundled template
        // is missing for a model.
        for device in loaded {
            let unmapped = DeviceDiagnostics.unmappedKeys(for: device)
            guard !unmapped.isEmpty else { continue }
            let summary = "\(device.model): \(unmapped.joined(separator: ", "))"
            Self.logger.notice("Reports keys no control shows, \(summary, privacy: .public)")
        }
        // Bind a shortcut for anything newly seen. Devices only exist after
        // the account loads, so this cannot be declared up front.
        shortcutBinder.bind(devices: loaded) { [weak self] serialNumber in
            self?.togglePower(serialNumber: serialNumber)
        }
        // Presets live in settings and only exist once they have been saved,
        // so binding them happens here alongside device binding.
        rebindPresets()
    }

    func subscribeToUpdates() {
        updatesTask?.cancel()
        updatesTask = Task {
            let stream = await socketService.observeUpdates()
            for await update in stream {
                apply(update)
            }
        }
    }

    func apply(_ update: DreoStateUpdate) {
        guard let index = devices.firstIndex(where: { $0.serialNumber == update.serialNumber }) else { return }
        devices[index].apply(update.changes)
        // A pushed report is confirmed truth in the same way an ack is: the
        // fan is the one saying it, not the app hoping a send landed.
        wireState[update.serialNumber, default: [:]].merge(update.changes) { _, pushed in pushed }
        // A fan that just pushed a report is plainly reachable. If the push
        // itself carried `connected`, that wins: it is fresher than anything
        // we could infer.
        if update.changes["connected"] == nil {
            markReachable(update.serialNumber)
        }
    }

    func scheduleSettingsSave() {
        settingsSaveTask?.cancel()
        let current = settings
        settingsSaveTask = Task { try? await settingsRepository.save(current) }
    }
}
