import XCTest
@testable import Windbar

/// Signing out is only useful if it is complete. A partial sign-out is worse than
/// none: it looks signed out while the app still holds a live token, or it drops the
/// token while leaving the password on disk so the next launch silently signs back in.
@MainActor
final class SignOutTests: XCTestCase {
    private func device(_ serialNumber: String) -> DreoDevice {
        DreoDevice(
            serialNumber: serialNumber,
            deviceName: "Fan \(serialNumber)",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: ["connected": .bool(true)]
        )
    }

    private func signedInModel(
        apiStub: DreoAPIServiceStub,
        socket: DreoSocketServiceFake,
        keychain: KeychainRepositoryFake,
        settings: SettingsRepositoryFake = SettingsRepositoryFake(
            stored: AppSettings(lastSelectedDeviceSerialNumber: "SN1", hasCompletedOnboarding: false)
        )
    ) async -> AppModel {
        await apiStub.setDevicesResult(.success([device("SN1"), device("SN2")]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let model = AppModel(
            apiService: apiStub,
            socketService: socket,
            keychainRepository: keychain,
            settingsRepository: settings
        )
        await model.start()
        return model
    }

    func test_signOut_clearsEverythingThatCouldSignTheUserBackIn() async {
        let apiStub = DreoAPIServiceStub()
        let socket = DreoSocketServiceFake()
        let keychain = KeychainRepositoryFake(
            stored: DreoCredentials(email: "user@example.com", password: "secret")
        )
        let model = await signedInModel(apiStub: apiStub, socket: socket, keychain: keychain)
        XCTAssertEqual(model.launchState, .ready)
        XCTAssertEqual(model.devices.count, 2)

        await model.signOut()

        XCTAssertEqual(model.launchState, .needsLogin)
        XCTAssertTrue(model.devices.isEmpty, "fans from the old account must not linger")

        let remaining = try? await keychain.loadCredentials()
        XCTAssertNil(remaining, "the password must not survive on disk")

        let signOuts = await apiStub.signOutCallCount
        XCTAssertEqual(signOuts, 1, "the in-memory access token must be dropped too")

        let stillConnected = await socket.connectedSession
        XCTAssertNil(stillConnected, "the realtime socket must be closed")

        XCTAssertNil(model.settings.lastSelectedDeviceSerialNumber,
                     "the hotkey must not point at a device from the previous account")
    }

    /// The whole point of signing out is that a relaunch does not restore the session.
    func test_afterSignOut_aRelaunchAsksForTheLoginAgain() async {
        let keychain = KeychainRepositoryFake(
            stored: DreoCredentials(email: "user@example.com", password: "secret")
        )
        let model = await signedInModel(
            apiStub: DreoAPIServiceStub(), socket: DreoSocketServiceFake(), keychain: keychain)
        await model.signOut()

        let relaunched = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: keychain,
            settingsRepository: SettingsRepositoryFake()
        )
        await relaunched.start()

        XCTAssertEqual(relaunched.launchState, .needsLogin)
    }
}
