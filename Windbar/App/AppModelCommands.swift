import Foundation
import os

// MARK: - Command delivery

extension AppModel {
    /// The switch a control depends on, if its schema declares one.
    ///
    /// The fan accepts a light colour while the ring is off, answers that it
    /// applied it, and stays dark. Nothing failed, so nothing could be
    /// reported, and the control simply looked broken. The schema says which
    /// switch has to be on, and that is enough to turn it on first.
    func requirement(forKey key: String, on device: DreoDevice) -> String? {
        (device.controlsConf?.control ?? [])
            .first { section in
                section.cmd == key || (section.items ?? []).contains { $0.cmd == key }
            }?
            .requires
    }

    /// Appends a delivery to a device's chain rather than launching it as an
    /// independent task, so at most one delivery is ever running for that
    /// device. The wire protocol carries no id correlating a reply to the
    /// command that caused it; without this, two batches issued back to back
    /// (two preset hotkeys pressed in quick succession, a batch overlapping a
    /// coalesced single send) interleave their commands and their replies.
    func enqueueDelivery(
        _ commands: [(key: String, value: DreoValue)],
        serialNumber: String,
        deviceName: String
    ) {
        let previous = deliveryChains[serialNumber]
        deliveryChains[serialNumber] = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.deliver(commands, serialNumber: serialNumber, deviceName: deviceName)
        }
    }

    func deliver(
        _ commands: [(key: String, value: DreoValue)],
        serialNumber: String,
        deviceName: String
    ) async {
        for (key, value) in commands {
            // The device can have been removed, or the account signed out,
            // while this delivery sat queued behind another one. Nothing is
            // left to talk to, and nothing here should be attributed to
            // whatever the screen shows now.
            guard devices.contains(where: { $0.serialNumber == serialNumber }) else { return }
            do {
                try await socketService.sendCommand(serialNumber: serialNumber, key: key, value: value)
                wireState[serialNumber, default: [:]][key] = value
                markReachable(serialNumber)
            } catch {
                Self.logger.warning("Command failed: \(String(describing: error), privacy: .public)")
                guard devices.contains(where: { $0.serialNumber == serialNumber }) else { return }
                // A refusal means the fan answered, so blaming the network
                // would send the user hunting a problem that isn't there.
                if case .rejected = error as? DreoSocketError {
                    errorMessage = "\(deviceName) wouldn't accept that setting."
                } else {
                    errorMessage = "Couldn't reach \(deviceName). Check your connection and try again."
                }
                await resyncState(serialNumber: serialNumber)
                return
            }
        }
    }

    /// Pulls the device's real state over REST after a failed delivery.
    ///
    /// `applyLocally` writes every command in a batch optimistically before
    /// any of them reach the wire, so a preset that fails partway through
    /// otherwise leaves the UI claiming the whole preset applied when the fan
    /// only has the commands that landed before the failure. A REST fetch is
    /// the one source of truth that does not depend on the socket that just
    /// failed.
    func resyncState(serialNumber: String) async {
        guard let index = devices.firstIndex(where: { $0.serialNumber == serialNumber }),
              let fetched = try? await apiService.fetchState(for: serialNumber) else { return }
        devices[index].apply(fetched)
        wireState[serialNumber] = devices[index].state
    }

    /// Stops every command still queued for one device: the pending debounce
    /// timers and the delivery chain. Called on device removal, so nothing
    /// already waiting fires afterwards and, on failure, reports an error
    /// about a fan that is no longer part of the account.
    func cancelPendingCommands(forSerialNumber serialNumber: String) {
        let prefix = "\(serialNumber)|"
        for (token, task) in pendingSends where token.hasPrefix(prefix) {
            task.cancel()
            pendingSends[token] = nil
        }
        deliveryChains[serialNumber]?.cancel()
        deliveryChains[serialNumber] = nil
    }

    /// The sign-out version of `cancelPendingCommands(forSerialNumber:)`: every
    /// device at once, since nothing queued for an account just signed out of
    /// should be able to reach the socket or the error banner.
    func cancelAllPendingCommands() {
        for task in pendingSends.values { task.cancel() }
        pendingSends.removeAll()
        for task in deliveryChains.values { task.cancel() }
        deliveryChains.removeAll()
    }
}
