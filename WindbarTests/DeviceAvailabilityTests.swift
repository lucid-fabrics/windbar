import XCTest
@testable import Windbar

final class DeviceAvailabilityTests: XCTestCase {
    private func device(
        serialNumber: String = "SN1",
        state: [String: DreoValue]
    ) -> DreoDevice {
        DreoDevice(
            serialNumber: serialNumber,
            deviceName: "Fan",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: state
        )
    }

    func test_isOnline_followsConnectedFlag() {
        XCTAssertTrue(device(state: ["connected": .bool(true)]).isOnline)
        XCTAssertFalse(device(state: ["connected": .bool(false)]).isOnline)
    }

    func test_isOnline_defaultsToTrueWhenDeviceNeverReportsIt() {
        // Staying quiet must not be mistaken for being unreachable.
        XCTAssertTrue(device(state: ["poweron": .bool(true)]).isOnline)
    }

    @MainActor
    private func readyModel(
        with devices: [DreoDevice],
        socket: DreoSocketServiceFake = DreoSocketServiceFake()
    ) async -> AppModel {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success(devices))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let model = AppModel(
            apiService: apiStub,
            socketService: socket,
            keychainRepository: KeychainRepositoryFake(
                stored: DreoCredentials(email: "user@example.com", password: "secret")
            ),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        return model
    }

    @MainActor
    func test_menuBarSymbol_showsOfflineRatherThanStaleRunningState() async {
        // The device still reports poweron == true, but it can't be reached,
        // so the icon must not claim it is running.
        let model = await readyModel(with: [
            device(state: ["poweron": .bool(true), "connected": .bool(false)])
        ])

        XCTAssertEqual(model.menuBarSymbol, "fan.slash")
    }

    @MainActor
    func test_hotkeyTargetSkipsOfflineDeviceWhenNothingWasChosen() async {
        let model = await readyModel(with: [
            device(serialNumber: "OFF", state: ["connected": .bool(false)]),
            device(serialNumber: "ON", state: ["connected": .bool(true)])
        ])

        XCTAssertEqual(model.lastSelectedOrFirstDevice?.serialNumber, "ON")
    }

    /// A fan paired moments ago is listed before Dreo's cloud marks it
    /// connected, so the first report it pushes has to clear the stale flag.
    @MainActor
    func test_pushedReport_clearsAStaleOfflineFlag() async {
        let socket = DreoSocketServiceFake()
        let model = await readyModel(
            with: [device(state: ["connected": .bool(false)])],
            socket: socket
        )
        XCTAssertFalse(model.devices[0].isOnline)

        // The model subscribes to updates in a task of its own, so a push
        // sent the instant start() returns can land before anyone listens.
        try? await Task.sleep(for: .milliseconds(400))
        await socket.push(DreoStateUpdate(serialNumber: "SN1", changes: ["poweron": .bool(true)]))

        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(model.devices[0].isOnline)
    }

    /// A push that says offline is fresher than anything we could infer.
    @MainActor
    func test_pushedReportSayingOffline_isRespected() async {
        let socket = DreoSocketServiceFake()
        let model = await readyModel(
            with: [device(state: ["connected": .bool(false)])],
            socket: socket
        )

        try? await Task.sleep(for: .milliseconds(400))
        await socket.push(DreoStateUpdate(serialNumber: "SN1", changes: ["connected": .bool(false)]))

        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(model.devices[0].isOnline)
    }

    /// The user's own escape hatch: the header power switch stays live on an
    /// offline card, and an acked command proves the fan is answering.
    @MainActor
    func test_ackedCommand_clearsAStaleOfflineFlag() async {
        let model = await readyModel(with: [device(state: ["connected": .bool(false)])])
        XCTAssertFalse(model.devices[0].isOnline)

        model.setValue(.bool(true), forKey: "poweron", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(model.devices[0].isOnline)
    }

    /// One dropped command is not proof a fan is gone.
    @MainActor
    func test_failedCommand_leavesTheFlagAlone() async {
        let socket = DreoSocketServiceFake()
        await socket.setSendCommandError(DreoSocketError.ackTimeout)
        let model = await readyModel(
            with: [device(state: ["connected": .bool(false)])],
            socket: socket
        )

        model.setValue(.bool(true), forKey: "poweron", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(model.devices[0].isOnline)
    }
}
