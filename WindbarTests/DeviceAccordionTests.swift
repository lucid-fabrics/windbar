import XCTest
@testable import Windbar

/// The accordion's own rules, tested at the level they are actually decided:
/// which fan `MenuBarView` should open on, given what the model knows.
///
/// The view's `@State` is not reachable from a test, so this pins the inputs
/// that drive `seedExpansion()` instead: the last-used serial, and whether it
/// still belongs to a device on the account. Getting that wrong is how every
/// card ends up shut with no obvious way to tell why.
@MainActor
final class DeviceAccordionTests: XCTestCase {
    private func device(_ serialNumber: String) -> DreoDevice {
        DreoDevice(
            serialNumber: serialNumber,
            deviceName: "Fan \(serialNumber)",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: ["connected": .bool(true), "poweron": .bool(true)]
        )
    }

    private func readyModel(devices: [DreoDevice]) async -> AppModel {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success(devices))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let model = AppModel(
            apiService: apiStub,
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        return model
    }

    /// The fan the accordion opens on is the same one the global hotkey and a
    /// device-less URL trigger already act on, so "the fan Windbar is
    /// currently about" stays one idea instead of two that usually agree.
    func test_lastUsedDevice_isTheOneTheAccordionShouldOpen() async {
        let model = await readyModel(devices: [device("SN1"), device("SN2")])

        model.setValue(.int(5), forKey: "windlevel", on: model.devices[1])

        XCTAssertEqual(model.settings.lastSelectedDeviceSerialNumber, "SN2")
        XCTAssertEqual(model.lastSelectedOrFirstDevice?.serialNumber, "SN2")
    }

    /// A serial stored from a previous account, or from a fan since removed,
    /// must not match anything: `seedExpansion()` falls back to the first
    /// device precisely because this lookup can come back empty.
    func test_aStoredSerialForAFanNoLongerPresent_matchesNoDevice() async {
        let model = await readyModel(devices: [device("SN1"), device("SN2")])
        model.settings.lastSelectedDeviceSerialNumber = "SN-GONE"

        let match = model.devices.first { $0.serialNumber == model.settings.lastSelectedDeviceSerialNumber }

        XCTAssertNil(match, "the fallback to devices.first is what keeps a card open")
        XCTAssertNotNil(model.devices.first)
    }

    /// One fan is rendered expanded unconditionally, so nothing about the
    /// accordion should depend on a stored serial in that case.
    func test_singleDevice_needsNoStoredSelectionToBeShown() async {
        let model = await readyModel(devices: [device("SN1")])

        XCTAssertEqual(model.devices.count, 1)
        XCTAssertEqual(model.lastSelectedOrFirstDevice?.serialNumber, "SN1")
    }

    /// Firing a preset counts as touching that fan, so the accordion opens on
    /// it next time rather than on whichever card happened to be first.
    func test_firingAPreset_marksThatFanAsLastUsed() async {
        let model = await readyModel(devices: [device("SN1"), device("SN2")])
        let preset = DevicePreset(name: "North", values: ["windlevel": .int(9)])
        model.savePreset(preset, on: model.devices[1])

        model.firePreset(id: preset.id, onSerialNumber: "SN2")

        XCTAssertEqual(model.settings.lastSelectedDeviceSerialNumber, "SN2")
    }
}
