import XCTest
@testable import Windbar

@MainActor
final class AppModelTests: XCTestCase {
    func test_start_noStoredCredentials_setsNeedsLogin() async {
        let model = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )

        await model.start()

        XCTAssertEqual(model.launchState, .needsLogin)
        XCTAssertTrue(model.devices.isEmpty)
    }

    func test_start_withStoredCredentials_reachesReadyWithDevices() async {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success([
            DreoDevice(serialNumber: "SN1", deviceName: "Tower Fan", model: "DR-HTF004S", controlsConf: nil)
        ]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let socketFake = DreoSocketServiceFake()

        let credentials = DreoCredentials(email: "user@example.com", password: "secret")
        let model = AppModel(
            apiService: apiStub,
            socketService: socketFake,
            keychainRepository: KeychainRepositoryFake(stored: credentials),
            settingsRepository: SettingsRepositoryFake()
        )

        await model.start()

        XCTAssertEqual(model.launchState, .ready)
        XCTAssertEqual(model.devices.map(\.serialNumber), ["SN1"])
        let connectedSession = await socketFake.connectedSession
        XCTAssertEqual(connectedSession?.accessToken, "tok")
    }

    func test_login_failure_setsErrorMessageAndNeedsLogin() async {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setLoginResult(.failure(DreoAPIError.apiError(code: 100_022, message: "bad credentials")))

        let model = AppModel(
            apiService: apiStub,
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )

        await model.login(email: "user@example.com", password: "wrong")

        XCTAssertEqual(model.launchState, .needsLogin)
        XCTAssertNotNil(model.errorMessage)
    }

    func test_togglePower_updatesLocalStateOptimisticallyAndSendsCommand() async {
        let device = DreoDevice(
            serialNumber: "SN1",
            deviceName: "Tower Fan",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: ["poweron": .bool(false)]
        )
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success([device]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let socketFake = DreoSocketServiceFake()

        let model = AppModel(
            apiService: apiStub,
            socketService: socketFake,
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()

        model.togglePower(for: model.devices[0])

        XCTAssertEqual(model.devices[0].isOn, true)

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.serialNumber, "SN1")
        XCTAssertEqual(sent.first?.key, "poweron")
        XCTAssertEqual(sent.first?.value, .bool(true))
    }

    func test_toggleLastSelectedDevicePower_fallsBackToFirstDeviceWhenNoneSelected() async {
        let devices = [
            DreoDevice(
                serialNumber: "SN1", deviceName: "Fan 1", model: "DR-HTF004S",
                controlsConf: nil, state: ["poweron": .bool(false)]
            ),
            DreoDevice(
                serialNumber: "SN2", deviceName: "Fan 2", model: "DR-HTF004S",
                controlsConf: nil, state: ["poweron": .bool(false)]
            )
        ]
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

        model.toggleLastSelectedDevicePower()

        XCTAssertEqual(model.devices.first(where: { $0.serialNumber == "SN1" })?.isOn, true)
    }

    func test_refreshDevices_picksUpNewlyPairedDevice() async {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success([
            DreoDevice(serialNumber: "SN1", deviceName: "Fan 1", model: "DR-HTF004S", controlsConf: nil)
        ]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))

        let model = AppModel(
            apiService: apiStub,
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        XCTAssertEqual(model.devices.map(\.serialNumber), ["SN1"])

        await apiStub.setDevicesResult(.success([
            DreoDevice(serialNumber: "SN1", deviceName: "Fan 1", model: "DR-HTF004S", controlsConf: nil),
            DreoDevice(serialNumber: "SN2", deviceName: "Fan 2 (new)", model: "DR-HTF004S", controlsConf: nil)
        ]))
        await model.refreshDevices()

        XCTAssertEqual(model.devices.map(\.serialNumber), ["SN1", "SN2"])
        XCTAssertFalse(model.isRefreshingDevices)
    }
}
