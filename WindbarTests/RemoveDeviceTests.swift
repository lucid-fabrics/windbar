import XCTest
@testable import Windbar

@MainActor
final class RemoveDeviceTests: XCTestCase {
    private func device(_ serialNumber: String) -> DreoDevice {
        DreoDevice(
            serialNumber: serialNumber,
            deviceName: "Fan \(serialNumber)",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: ["connected": .bool(true)]
        )
    }

    private func readyModel(
        devices: [DreoDevice],
        apiStub: DreoAPIServiceStub,
        settings: SettingsRepositoryFake = SettingsRepositoryFake()
    ) async -> AppModel {
        await apiStub.setDevicesResult(.success(devices))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let model = AppModel(
            apiService: apiStub,
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(
                stored: DreoCredentials(email: "user@example.com", password: "secret")
            ),
            settingsRepository: settings
        )
        await model.start()
        return model
    }

    func test_removeDevice_unbindsAndDropsItFromTheList() async {
        let apiStub = DreoAPIServiceStub()
        let model = await readyModel(devices: [device("SN1"), device("SN2")], apiStub: apiStub)

        await model.removeDevice(model.devices[0])

        XCTAssertEqual(model.devices.map(\.serialNumber), ["SN2"])
        let removed = await apiStub.removedSerialNumbers
        XCTAssertEqual(removed, ["SN1"])
        XCTAssertNil(model.errorMessage)
    }

    func test_removeDevice_clearsHotkeyTargetWhenItWasTheRemovedOne() async {
        let apiStub = DreoAPIServiceStub()
        let settings = SettingsRepositoryFake(
            stored: AppSettings(lastSelectedDeviceSerialNumber: "SN1", hasCompletedOnboarding: false)
        )
        let model = await readyModel(devices: [device("SN1"), device("SN2")], apiStub: apiStub, settings: settings)
        XCTAssertEqual(model.lastSelectedOrFirstDevice?.serialNumber, "SN1")

        await model.removeDevice(model.devices[0])

        // The hotkey must not keep pointing at a device that no longer exists.
        XCTAssertEqual(model.lastSelectedOrFirstDevice?.serialNumber, "SN2")
    }

    func test_removeDevice_keepsDeviceWhenTheServerRefuses() async {
        struct Refused: Error {}
        let apiStub = DreoAPIServiceStub()
        await apiStub.setRemoveResult(.failure(Refused()))
        let model = await readyModel(devices: [device("SN1")], apiStub: apiStub)

        await model.removeDevice(model.devices[0])

        // A failed unbind must not make the device vanish locally, or the
        // list would disagree with the account.
        XCTAssertEqual(model.devices.map(\.serialNumber), ["SN1"])
        XCTAssertNotNil(model.errorMessage)
    }
}
