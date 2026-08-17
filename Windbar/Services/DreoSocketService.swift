import Foundation
import os

/// Live control channel for Dreo devices. Protocol reverse-engineered from
/// the vendored Python client: `wss://wsb-{region}.dreo-tech.com/websocket`,
/// a literal `"2"` text-frame keepalive every 15s, and JSON command/ack
/// envelopes keyed by device serial (`devicesn`).
actor DreoSocketService: DreoSocketServiceProtocol {
    private static let logger = Logger(subsystem: "com.lucidfabrics.windbar", category: "DreoSocketService")

    private let urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: DreoSession?
    private var shouldReconnect = false

    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private var updateContinuations: [UUID: AsyncStream<DreoStateUpdate>.Continuation] = [:]
    /// Acks matched to the command that earned them, keyed `serial|cmd`, and
    /// holding the value the reply actually echoed.
    ///
    /// Keying by device alone looked fine until two commands were in flight
    /// at once, e.g. dragging a slider. Then the first reply satisfied
    /// whichever command happened to look first, the others waited out their
    /// timeout, and the retry resent a value the user had already dragged
    /// past. The fan refused the stale instruction, so a control nobody
    /// touched reported a failure. The reply echoes the key it applied, so
    /// match on that.
    ///
    /// Holding the value too closes a second gap: firmware also pushes
    /// ambient reports for a key under this same name (a fan settling on a
    /// value on its own), and an echo carrying a *different* value than what
    /// was sent is that, not a confirmation, and must not ack the command.
    /// The caller is now guaranteed to have at most one command in flight per
    /// device (`AppModel` serializes delivery), so a matching value is also
    /// no longer ambiguous between two commands wanting the same key.
    private var acknowledgedCommands: [String: DreoValue] = [:]
    /// Fallback for a reply that acknowledges without echoing a key. Only
    /// trusted while a single command is in flight for that device, since
    /// that is the one case where it cannot be attributed to the wrong one.
    private var acknowledgedSerialNumbers: Set<String> = []
    private var inFlightCounts: [String: Int] = [:]
    /// Rejections waiting to be picked up by the send that caused them.
    private var rejections: [String: DreoSocketError] = [:]

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func observeUpdates() async -> AsyncStream<DreoStateUpdate> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: DreoStateUpdate.self)
        updateContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(id) }
        }
        return stream
    }

    func connect(session: DreoSession) async {
        self.session = session
        shouldReconnect = true
        openSocket()
    }

    func disconnect() async {
        shouldReconnect = false
        reconnectTask?.cancel()
        pingTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func sendCommand(serialNumber: String, key: String, value: DreoValue) async throws {
        let text = try Self.encodeCommand(serialNumber: serialNumber, key: key, value: value)

        var lastError: Error = DreoSocketError.notConnected
        for attempt in 0...Constants.Socket.maxCommandRetries {
            do {
                try await sendAndAwaitAck(serialNumber: serialNumber, key: key, value: value, text: text)
                return
            } catch {
                lastError = error
                // Name the command, not just the failure. A bare "instruction
                // validate failed" cannot be acted on; knowing which key the
                // fan refused is the whole diagnosis.
                let description = "\(key)=\(value): \(String(describing: error))"
                Self.logger.warning("Command attempt \(attempt + 1) failed, \(description, privacy: .public)")
                // A refused value stays refused, so resending it only earns
                // the same answer twice more.
                if let socketError = error as? DreoSocketError, !socketError.isRetryable {
                    throw socketError
                }
            }
        }
        throw lastError
    }

    // MARK: - Connection lifecycle

    private func openSocket() {
        guard let session, let url = Self.webSocketURL(for: session) else {
            Self.logger.error("No session or invalid websocket URL")
            return
        }

        Self.logger.debug("Opening socket: \(url.absoluteString, privacy: .public)")
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveTask?.cancel()
        receiveTask = Task { await self.receiveLoop() }

        pingTask?.cancel()
        pingTask = Task { await self.pingLoop() }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: Constants.Socket.reconnectDelay)
            guard !Task.isCancelled else { return }
            self.reopenIfNeeded()
        }
    }

    private func reopenIfNeeded() {
        guard shouldReconnect else { return }
        openSocket()
    }

    private func removeContinuation(_ id: UUID) {
        updateContinuations.removeValue(forKey: id)
    }

    // MARK: - Loops

    private func pingLoop() async {
        while !Task.isCancelled {
            guard let webSocketTask else { return }
            do {
                try await webSocketTask.send(.string(Constants.Socket.pingMessage))
            } catch {
                Self.logger.warning("Ping failed: \(String(describing: error), privacy: .public)")
                scheduleReconnect()
                return
            }
            try? await Task.sleep(for: Constants.Socket.pingInterval)
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let webSocketTask else { return }
            do {
                let message = try await webSocketTask.receive()
                handle(message: message)
            } catch {
                Self.logger.warning("Receive failed: \(String(describing: error), privacy: .public)")
                scheduleReconnect()
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message else { return }
        Self.logger.debug("Received: \(text, privacy: .public)")

        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(SocketEnvelope.self, from: data) else {
            return
        }

        // A refusal names the device like any other frame, so counting it as
        // an ack made a rejected command look like it worked: the value never
        // changed and nothing was reported. Take it as the failure it is, and
        // keep its error_msg/error_code out of the state, since merging them
        // would leave the device carrying keys that are not settings.
        if let failure = envelope.failure {
            Self.logger.warning("Command refused: \(String(describing: failure), privacy: .public)")
            rejections[envelope.devicesn] = failure
            return
        }

        // Any other message naming the device counts as an ack: real firmware
        // sends "report" for both command confirmations and ambient sensor
        // pushes, not the "control-report"/"control-reply" names the vendored
        // Python client's source assumed, so a strict method-name match never
        // fires.
        acknowledgedSerialNumbers.insert(envelope.devicesn)

        if let reported = envelope.reported {
            for (key, value) in reported {
                acknowledgedCommands[Self.token(envelope.devicesn, key)] = value
            }
            let update = DreoStateUpdate(serialNumber: envelope.devicesn, changes: reported)
            for continuation in updateContinuations.values {
                continuation.yield(update)
            }
        }
    }

    // MARK: - Command send + ack

    // ponytail: polls every 100ms instead of a continuation-based wakeup.
    // Simpler and avoids actor-isolation pitfalls with cross-task continuations;
    // upgrade to a per-command CheckedContinuation registry if 100ms of added
    // latency on the rare retry path ever actually matters.
    private func sendAndAwaitAck(serialNumber: String, key: String, value: DreoValue, text: String) async throws {
        guard let webSocketTask else { throw DreoSocketError.notConnected }
        let token = Self.token(serialNumber, key)
        acknowledgedCommands.removeValue(forKey: token)
        acknowledgedSerialNumbers.remove(serialNumber)
        rejections.removeValue(forKey: serialNumber)

        // The caller guarantees at most one command per device in flight, so
        // this is normally always 1. Kept rather than assumed: a caller that
        // ever violates that guarantee should get a wrong ack, not a crash.
        inFlightCounts[serialNumber, default: 0] += 1
        defer {
            let remaining = (inFlightCounts[serialNumber] ?? 1) - 1
            inFlightCounts[serialNumber] = remaining > 0 ? remaining : nil
        }

        Self.logger.debug("Sending: \(text, privacy: .public)")
        try await webSocketTask.send(.string(text))

        let deadline = ContinuousClock.now + Constants.Socket.commandAckTimeout
        while ContinuousClock.now < deadline {
            if let rejection = rejections.removeValue(forKey: serialNumber) {
                throw rejection
            }
            // A mismatched value is a report about something else, e.g. the
            // fan settling on a value on its own, not a confirmation of what
            // was just sent, so it is left in place rather than consumed.
            if let acked = acknowledgedCommands[token], acked == value {
                acknowledgedCommands.removeValue(forKey: token)
                Self.logger.debug("Acked: \(token, privacy: .public)")
                return
            }
            // Only safe while nothing else is waiting: with one command in
            // flight there is no other command this ack could belong to.
            if inFlightCounts[serialNumber] == 1, acknowledgedSerialNumbers.remove(serialNumber) != nil {
                Self.logger.debug("Acked without echo: \(token, privacy: .public)")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DreoSocketError.ackTimeout
    }

    private static func token(_ serialNumber: String, _ key: String) -> String {
        "\(serialNumber)|\(key)"
    }

    // MARK: - Wire helpers

    private struct SocketEnvelope: Decodable {
        let devicesn: String
        let method: String
        let reported: [String: DreoValue]?

        /// The fan answers an unacceptable value with an error payload in
        /// the same shape a report arrives in, e.g.
        /// `{"error_msg": "instruction validate failed", "error_code": 500003}`.
        var failure: DreoSocketError? {
            guard let reported,
                  reported["error_code"] != nil || reported["error_msg"] != nil else { return nil }
            return .rejected(
                code: reported["error_code"]?.intValue,
                message: reported["error_msg"]?.stringValue
            )
        }
    }

    static func encodeCommand(serialNumber: String, key: String, value: DreoValue) throws -> String {
        let payload: [String: Any] = [
            "devicesn": serialNumber,
            "method": "control",
            "params": [key: value.jsonObject],
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DreoSocketError.notConnected
        }
        return text
    }

    static func webSocketURL(for session: DreoSession) -> URL? {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "wsb-\(session.regionHost).dreo-tech.com"
        components.path = "/websocket"
        components.queryItems = [
            URLQueryItem(name: "accessToken", value: session.accessToken),
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        return components.url
    }
}
