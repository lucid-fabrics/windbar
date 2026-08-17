@testable import Windbar

actor DreoAPIServiceStub: DreoAPIServiceProtocol {
    var loginResult: Result<Void, Error> = .success(())
    var devicesResult: Result<[DreoDevice], Error> = .success([])
    var stateResult: Result<[String: DreoValue], Error> = .success([:])
    var sessionToReturn: DreoSession?

    private(set) var loginCallCount = 0
    private(set) var listDevicesCallCount = 0
    private(set) var signOutCallCount = 0

    func signOut() async {
        signOutCallCount += 1
        sessionToReturn = nil
    }

    func login(_ credentials: DreoCredentials) async throws {
        loginCallCount += 1
        try loginResult.get()
    }

    func listDevices() async throws -> [DreoDevice] {
        listDevicesCallCount += 1
        return try devicesResult.get()
    }

    func fetchState(for serialNumber: String) async throws -> [String: DreoValue] {
        try stateResult.get()
    }

    private(set) var removedSerialNumbers: [String] = []
    var removeResult: Result<Void, Error> = .success(())

    func removeDevice(serialNumber: String) async throws {
        removedSerialNumbers.append(serialNumber)
        try removeResult.get()
    }

    func setRemoveResult(_ result: Result<Void, Error>) {
        removeResult = result
    }

    func currentSession() async -> DreoSession? {
        sessionToReturn
    }

    func setLoginResult(_ result: Result<Void, Error>) {
        loginResult = result
    }

    func setDevicesResult(_ result: Result<[DreoDevice], Error>) {
        devicesResult = result
    }

    func setStateResult(_ result: Result<[String: DreoValue], Error>) {
        stateResult = result
    }

    func setSession(_ session: DreoSession?) {
        sessionToReturn = session
    }
}
