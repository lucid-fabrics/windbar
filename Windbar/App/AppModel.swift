import Foundation
import Observation
import os

@MainActor
@Observable
final class AppModel {
    enum LaunchState: Equatable {
        case loading
        case needsLogin
        case ready
    }

    // internal(set) rather than private(set): the lifecycle internals
    // (login, device loading, the update stream) live in
    // AppModelLifecycle.swift, a separate file, so `private` would not
    // reach them. Same reasoning as apiService/socketService below.
    internal(set) var launchState: LaunchState = .loading
    internal(set) var devices: [DreoDevice] = []
    private(set) var isRefreshingDevices = false

    /// Set only when the user picks "Add a Device". macOS opens an app's
    /// window scene simply because the app was activated, so the pairing
    /// wizard needs a way to tell a real request from that.
    var hasRequestedPairing = false
    var errorMessage: String?

    var settings: AppSettings = .default {
        didSet {
            guard hasLoadedSettings else { return }
            scheduleSettingsSave()
        }
    }

    @ObservationIgnored static let logger = Logger(subsystem: "com.lucidfabrics.windbar", category: "AppModel")

    @ObservationIgnored let apiService: DreoAPIServiceProtocol
    @ObservationIgnored let socketService: DreoSocketServiceProtocol
    @ObservationIgnored let keychainRepository: KeychainRepositoryProtocol
    @ObservationIgnored let settingsRepository: SettingsRepositoryProtocol

    #if WINDBAR_DONATIONS
    /// Direct-download build only. See Models/Donations.swift.
    let donations = DonationCoordinator()
    #endif

    #if WINDBAR_DIRECT
    /// Direct-download build only. Held here so it is constructed once for
    /// the app's lifetime: Sparkle's scheduled checks start with it, and a
    /// controller rebuilt per view would restart that clock every time the
    /// popover opened. See App/UpdateController.swift.
    let updates = UpdateController()
    #endif

    @ObservationIgnored let shortcutBinder = DeviceShortcutBinder()
    @ObservationIgnored private var hasLoadedSettings = false
    @ObservationIgnored var settingsSaveTask: Task<Void, Never>?
    @ObservationIgnored var updatesTask: Task<Void, Never>?
    /// One pending send per `serial|cmd`, so a control being dragged replaces
    /// its own in-flight value instead of racing it. See AppModelCommands.swift.
    @ObservationIgnored var pendingSends: [String: Task<Void, Never>] = [:]
    /// One delivery chain per device, so at most one command is ever in
    /// flight per device. See `enqueueDelivery` in AppModelCommands.swift.
    @ObservationIgnored var deliveryChains: [String: Task<Void, Never>] = [:]
    /// The fan's confirmed state per device, as opposed to `device.state`'s
    /// optimistic one. See the property comment in AppModelCommands.swift.
    @ObservationIgnored var wireState: [String: [String: DreoValue]] = [:]

    init(
        apiService: DreoAPIServiceProtocol = DreoAPIService(),
        socketService: DreoSocketServiceProtocol = DreoSocketService(),
        keychainRepository: KeychainRepositoryProtocol = KeychainRepository(),
        settingsRepository: SettingsRepositoryProtocol = SettingsRepository()
    ) {
        self.apiService = apiService
        self.socketService = socketService
        self.keychainRepository = keychainRepository
        self.settingsRepository = settingsRepository
    }

    /// Target for a `windbar://` URL that names no device. An explicit choice
    /// is honoured even while it's offline, but the automatic fallback skips
    /// unreachable devices so the hotkey acts on one that can respond.
    var lastSelectedOrFirstDevice: DreoDevice? {
        if let serialNumber = settings.lastSelectedDeviceSerialNumber,
           let match = devices.first(where: { $0.serialNumber == serialNumber }) {
            return match
        }
        return devices.first(where: \.isOnline) ?? devices.first
    }

    /// Menu bar icon. Only shows running when a device is genuinely both
    /// reachable and on, so a stale "on" from an offline fan doesn't read as
    /// though it's still blowing.
    var menuBarSymbol: String {
        guard let device = lastSelectedOrFirstDevice else { return "fan" }
        guard device.isOnline else { return "fan.slash" }
        return device.isOn ? "fan.fill" : "fan"
    }

    func start() async {
        settings = await settingsRepository.load()
        hasLoadedSettings = true

        guard let credentials = try? await keychainRepository.loadCredentials() else {
            launchState = .needsLogin
            return
        }
        await login(credentials: credentials, persist: false)
    }

    func login(email: String, password: String) async {
        await login(credentials: DreoCredentials(email: email, password: password), persist: true)
    }

    /// Sets one control, coalescing repeats of the same control.
    ///
    /// A slider reports every step it crosses, so one drag used to fire a
    /// command per step. Only the value the user let go on matters, and the
    /// ones before it were actively harmful: they raced each other to the
    /// socket, and a command that lost its ack got retried with a value the
    /// user had already dragged past, which the fan then refused. Local state
    /// still moves on every step, so the UI tracks the drag; only the wire
    /// waits for the drag to settle.
    func setValue(_ value: DreoValue, forKey key: String, on device: DreoDevice) {
        // Switch on whatever this control depends on first. The rule lives
        // here rather than in the card so a keyboard shortcut, a URL trigger
        // and a click all behave the same. Decided from `wireState`, the
        // fan's confirmed state, not `device.state`: that optimistic copy
        // already reads true the instant the first tap fires, so a second
        // tap within the debounce window would otherwise drop the switch-on
        // from its own batch and send a colour to a ring still off.
        //
        // The prerequisite rides inside the coalesced batch rather than going
        // out on its own. Sending it immediately would exempt every control
        // that has one from coalescing, and the light's own speed slider has
        // one, so dragging it with the ring off put the whole flood straight
        // back: five redundant switch-ons racing five values.
        var commands: [(key: String, value: DreoValue)] = []
        if let required = requirement(forKey: key, on: device),
           wireState[device.serialNumber]?[required]?.boolValue != true {
            commands.append((required, .bool(true)))
        }
        commands.append((key, value))

        applyLocally(commands, to: device)

        let token = "\(device.serialNumber)|\(key)"
        pendingSends[token]?.cancel()
        let serialNumber = device.serialNumber
        let deviceName = device.deviceName
        pendingSends[token] = Task { [weak self] in
            try? await Task.sleep(for: Constants.Socket.controlSettleDelay)
            guard !Task.isCancelled, let self else { return }
            self.pendingSends[token] = nil
            self.enqueueDelivery(commands, serialNumber: serialNumber, deviceName: deviceName)
        }
    }

    /// Sends a batch of commands to one device, in the order given.
    ///
    /// Order is the point. A fan that is off ignores a speed change, so a
    /// preset has to land power before the rest. Going through the same
    /// per-device delivery chain as a coalesced single send is what makes
    /// that order hold against the wire and not just within this call: two
    /// batches issued back to back, e.g. two preset hotkeys pressed in quick
    /// succession, would otherwise race each other's commands.
    func send(_ commands: [(key: String, value: DreoValue)], to device: DreoDevice) {
        guard !commands.isEmpty else { return }
        applyLocally(commands, to: device)

        let serialNumber = device.serialNumber
        let deviceName = device.deviceName
        // A batch is one deliberate action, e.g. running a preset, so it goes
        // as sent rather than being coalesced. Any single-control send still
        // pending for these keys would only undo it.
        for (key, _) in commands {
            pendingSends.removeValue(forKey: "\(serialNumber)|\(key)")?.cancel()
        }
        enqueueDelivery(commands, serialNumber: serialNumber, deviceName: deviceName)
    }

    /// Optimistic local state, so the UI answers the click immediately and a
    /// second keypress sees the state the first one asked for.
    func applyLocally(_ commands: [(key: String, value: DreoValue)], to device: DreoDevice) {
        guard let index = devices.firstIndex(where: { $0.serialNumber == device.serialNumber }) else { return }
        for (key, value) in commands {
            devices[index].state[key] = value
        }
        settings.lastSelectedDeviceSerialNumber = device.serialNumber
    }

    /// Promotes a device the account still lists as offline back to online.
    ///
    /// `connected` is read once from REST when devices load, and a fan paired
    /// moments ago is routinely listed before Dreo's cloud has marked it
    /// connected. Nothing refreshed that flag afterwards, so a perfectly
    /// reachable fan stayed greyed out until the user hit Refresh Devices.
    /// An acked command or a pushed report is direct proof the fan is
    /// answering, and direct proof outranks a stale snapshot.
    ///
    /// Only ever promotes. Demotion stays with the REST refresh, since one
    /// dropped command is not proof a fan is gone and flipping the card to
    /// disabled on a transient failure would be worse than the stale flag.
    func markReachable(_ serialNumber: String) {
        guard let index = devices.firstIndex(where: { $0.serialNumber == serialNumber }),
              devices[index].state["connected"]?.boolValue == false else { return }
        devices[index].state["connected"] = .bool(true)
    }

    /// Current login session, including the numeric account id BLE pairing
    /// needs to bind a new fan to this account.
    func currentSession() async -> DreoSession? {
        await apiService.currentSession()
    }

    /// Unbinds a device from the Dreo account. This affects the account, not
    /// just this app, so callers must confirm with the user first.
    func removeDevice(_ device: DreoDevice) async {
        do {
            try await apiService.removeDevice(serialNumber: device.serialNumber)
            devices.removeAll { $0.serialNumber == device.serialNumber }
            wireState[device.serialNumber] = nil
            // A command already queued behind another for this device would
            // otherwise still fire after removal and, on failure, could
            // surface "Couldn't reach <device>" for a fan that is no longer
            // part of the account.
            cancelPendingCommands(forSerialNumber: device.serialNumber)
            if settings.lastSelectedDeviceSerialNumber == device.serialNumber {
                settings.lastSelectedDeviceSerialNumber = nil
            }
            // Drop the presets that lived on this device, and their key
            // combos with them, the same way deleting one preset already
            // does. Without this the combo sits in KeyboardShortcuts'
            // storage forever, unreachable by any UI (the row is gone) and
            // unreachable by collision detection (ShortcutRegistry.names now
            // only looks at presets belonging to a currently loaded device),
            // so a key nobody can free stays claimed indefinitely.
            unbindPresets(forSerialNumber: device.serialNumber)
            settings.presetsBySerialNumber[device.serialNumber] = nil
        } catch {
            Self.logger.warning("Remove failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't remove \(device.deviceName). Check your connection and try again."
        }
    }

    func togglePower(for device: DreoDevice) {
        setValue(.bool(!device.isOn), forKey: device.powerKey, on: device)
        #if WINDBAR_DONATIONS
        // Every power toggle routes through here: the popover, a device shortcut
        // and a URL trigger all call it. Counting anywhere else would miss two.
        donations.recordToggle()
        #endif
    }

    func toggleLastSelectedDevicePower() {
        guard let device = lastSelectedOrFirstDevice else { return }
        togglePower(for: device)
    }

    /// Toggles one specific device, used by that device's own keyboard
    /// shortcut. Silently does nothing if the device is gone or unreachable,
    /// since a keypress has nowhere to report an error.
    func togglePower(serialNumber: String) {
        guard let device = devices.first(where: { $0.serialNumber == serialNumber }),
              device.isOnline else { return }
        togglePower(for: device)
    }

    /// Sets one control on one device, used by URL triggers.
    func setValue(_ value: DreoValue, forKey key: String, onSerialNumber serialNumber: String) {
        guard let device = devices.first(where: { $0.serialNumber == serialNumber }),
              device.isOnline else { return }
        setValue(value, forKey: key, on: device)
    }

    /// Nudges a numeric control up or down, clamped to the range the device
    /// itself publishes.
    ///
    /// Relative steps are what a single key wants: one button for "faster"
    /// beats twelve buttons for each speed. The range comes from the device
    /// schema, so this cannot push a value the hardware would reject.
    func adjustValue(forKey key: String, by delta: Int, onSerialNumber serialNumber: String) {
        guard let device = devices.first(where: { $0.serialNumber == serialNumber }),
              device.isOnline else { return }

        let values = (device.controlsConf?.control ?? [])
            .flatMap { $0.items ?? [] }
            .filter { $0.cmd == key }
            .compactMap(\.value.intValue)

        guard let low = values.min(), let high = values.max(), low < high else { return }
        let current = device.state[key]?.intValue ?? low
        let next = min(max(current + delta, low), high)
        guard next != current else { return }

        setValue(.int(next), forKey: key, on: device)
    }

    /// Re-lists devices on the account. Picks up anything newly paired,
    /// whether through this app's own BLE provisioning or the official
    /// Dreo app.
    func refreshDevices() async {
        guard !isRefreshingDevices else { return }
        isRefreshingDevices = true
        defer { isRefreshingDevices = false }

        do {
            try await loadDevices()
        } catch {
            Self.logger.warning("Refresh failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't refresh devices. Check your connection and try again."
        }
    }

    /// Forget the account: no way back in without typing the password again.
    ///
    /// Order matters. Stop the socket and the update stream first, or an in-flight
    /// update can repopulate `devices` after they are cleared and leave the popover
    /// showing fans belonging to an account that is no longer signed in.
    ///
    /// `settings.presetsBySerialNumber` is deliberately left untouched: signing
    /// back into the same account should find the same presets, not an empty
    /// list. Nothing needs to unbind their shortcuts either. `devices` is
    /// cleared below, and every preset trigger (`firePreset`) already starts
    /// by looking its device up in `devices`, so a key press for any of them
    /// resolves to nothing the instant the account is gone, the same way a
    /// removed device's own toggle shortcut already does. The one real risk,
    /// a preset from a different, still-settings-resident account blocking a
    /// new shortcut as a false collision, is closed in `ShortcutRegistry.names`,
    /// which only considers presets belonging to a currently loaded device.
    func signOut() async {
        updatesTask?.cancel()
        updatesTask = nil
        // Same reasoning as the per-device drain in removeDevice, for every
        // device at once: nothing queued for an account just signed out of
        // should be able to reach the socket or the error banner.
        cancelAllPendingCommands()
        await socketService.disconnect()
        await apiService.signOut()

        // The Keychain item is the thing that survives a relaunch, so a failure here
        // is the one that actually matters: report it rather than pretending.
        do {
            try await keychainRepository.deleteCredentials()
        } catch {
            Self.logger.error("Sign out could not clear the Keychain: \(String(describing: error), privacy: .public)")
            errorMessage = "Signed out, but your password could not be removed from the Keychain."
        }

        devices = []
        wireState = [:]
        // Unbind every per-device hotkey. Leaving them registered means a keypress
        // fires at a device list that no longer exists.
        shortcutBinder.bind(devices: []) { _ in }
        settings.lastSelectedDeviceSerialNumber = nil
        launchState = .needsLogin
    }
}
