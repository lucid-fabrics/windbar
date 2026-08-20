import Foundation
@testable import Windbar

struct SentCommand: Equatable {
    let serialNumber: String
    let key: String
    let value: DreoValue
}

actor DreoSocketServiceFake: DreoSocketServiceProtocol {
    private(set) var connectedSession: DreoSession?
    private(set) var sentCommands: [SentCommand] = []
    var sendCommandError: Error?
    /// Fails only the first command whose key matches, then behaves
    /// normally. For proving a batch failure is attributed to the command
    /// that actually failed, not a sibling waiting for its own ack.
    var failOnceForKey: String?
    /// Held before returning, so a test can force two sends to overlap in
    /// time and prove whatever serializes them actually does.
    var artificialDelay: Duration?

    private var continuation: AsyncStream<DreoStateUpdate>.Continuation?

    func connect(session: DreoSession) async {
        connectedSession = session
    }

    func disconnect() async {
        connectedSession = nil
    }

    func sendCommand(serialNumber: String, key: String, value: DreoValue) async throws {
        if let artificialDelay {
            try? await Task.sleep(for: artificialDelay)
        }
        sentCommands.append(SentCommand(serialNumber: serialNumber, key: key, value: value))
        if failOnceForKey == key {
            failOnceForKey = nil
            throw DreoSocketError.rejected(code: 500_003, message: "instruction validate failed")
        }
        if let sendCommandError {
            throw sendCommandError
        }
    }

    func observeUpdates() async -> AsyncStream<DreoStateUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: DreoStateUpdate.self)
        self.continuation = continuation
        return stream
    }

    func push(_ update: DreoStateUpdate) {
        continuation?.yield(update)
    }

    func setSendCommandError(_ error: Error?) {
        sendCommandError = error
    }

    func setFailOnceForKey(_ key: String?) {
        failOnceForKey = key
    }

    func setArtificialDelay(_ duration: Duration?) {
        artificialDelay = duration
    }
}

extension AppModel {
    /// Waits for everything a control change sets in motion: the coalescing
    /// debounce, then the delivery itself.
    ///
    /// A fixed sleep used to be enough. It stopped being enough once a batch
    /// started parking between a switch-on and the value that depends on it,
    /// and padding every test by that pause would have bought nothing but a
    /// slower suite and a new number to keep in sync with the constant.
    func settleDeliveries(forSerialNumber serialNumber: String) async {
        try? await Task.sleep(for: Constants.Socket.controlSettleDelay + .milliseconds(120))
        await deliveryChains[serialNumber]?.value
    }
}
