import XCTest
@testable import Windbar

/// Phase 1 of the audit remediation: the Dreo wire protocol carries no id
/// correlating a reply to the command that caused it, so any scheme letting
/// two commands be in flight to one device at once is guessing which reply
/// belongs to which command. These tests cover what a single per-device
/// delivery chain and a confirmed-state shadow (`wireState`) fix at the
/// `AppModel` layer.
///
/// Not covered here: the value-matching ack logic added to the real
/// `DreoSocketService` (an echo with a different value than what was sent is
/// a report, not an ack). `DreoSocketServiceFake` does not model acks or
/// retries at all, so that half of the fix has no unit harness and was
/// instead verified against the real 508S: a rapid slider drag with the
/// light ring off, twice, with zero refusals both times.
@MainActor
final class DeliveryPipelineTests: XCTestCase {
    private func schema() -> ControlSchema {
        ControlSchema(
            control: [
                ControlSection(
                    rawId: "110", type: "Speed", title: "Speed", cmd: nil,
                    items: [ControlItem(text: "9", cmd: "windlevel", value: .int(9))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: nil
                ),
                ControlSection(
                    rawId: "295", type: "Toggle", title: "Ambient Light", cmd: "atmon",
                    items: nil, reverse: false, trueValue: nil, falseValue: nil, requires: nil
                ),
                ControlSection(
                    rawId: "315", type: "Color", title: "Light Colour", cmd: nil,
                    items: [ControlItem(text: "Red", cmd: "atmcolor", value: .int(0xFF0000))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: "atmon"
                )
            ],
            preference: []
        )
    }

    private struct Fixture {
        let model: AppModel
        let apiStub: DreoAPIServiceStub
        let socket: DreoSocketServiceFake
    }

    private func readyModel(atmon: Bool = false) async -> Fixture {
        let device = DreoDevice(
            serialNumber: "SN1",
            deviceName: "Air Circulator",
            model: "DR-HPF008S",
            controlsConf: schema(),
            state: ["poweron": .bool(true), "windlevel": .int(1), "atmon": .bool(atmon)]
        )
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success([device]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let socket = DreoSocketServiceFake()
        let model = AppModel(
            apiService: apiStub,
            socketService: socket,
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        return Fixture(model: model, apiStub: apiStub, socket: socket)
    }

    // MARK: - The bug the audit actually found

    /// The regression that matters most. `applyLocally` writes the
    /// prerequisite optimistically the instant the first tap fires, and
    /// SwiftUI rebuilds well inside the 180ms settle window, so a second tap
    /// reading a freshly-optimistic `device.state` would see the light
    /// already "on" and drop the switch-on from its own replacement batch.
    /// Deciding from `wireState`, which only an ack or a pushed report can
    /// move, is what keeps the switch-on in the batch until the fan has
    /// actually confirmed it.
    func test_prerequisite_isDecidedFromConfirmedStateNotOptimisticState() async {
        let fixture = await readyModel(atmon: false)
        let (model, socket) = (fixture.model, fixture.socket)

        model.setValue(.int(0xFF0000), forKey: "atmcolor", on: model.devices[0])
        // The optimistic write a live view would see if it rebuilt right now.
        XCTAssertEqual(model.devices[0].state["atmon"], .bool(true))

        // A second tap, using that freshly-optimistic device the way a real
        // rebuild would, before the fan has answered anything.
        model.setValue(.int(0x00FF00), forKey: "atmcolor", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["atmon", "atmcolor"], "the switch-on must survive the second tap")
        XCTAssertEqual(sent.last?.value, .int(0x00FF00))
    }

    // MARK: - Serialization

    func test_twoBatchesToTheSameDevice_doNotInterleave() async {
        let fixture = await readyModel()
        let (model, socket) = (fixture.model, fixture.socket)
        await socket.setArtificialDelay(.milliseconds(80))

        // Two preset hotkeys pressed in quick succession.
        model.send([("windlevel", .int(3)), ("atmon", .bool(true))], to: model.devices[0])
        model.send([("windlevel", .int(7)), ("atmon", .bool(false))], to: model.devices[0])

        try? await Task.sleep(for: .milliseconds(500))
        let sent = await socket.sentCommands
        XCTAssertEqual(
            sent.map { "\($0.key)=\($0.value)" },
            ["windlevel=3", "atmon=true", "windlevel=7", "atmon=false"],
            "the second batch must not start until the first has fully landed"
        )
    }

    func test_batchAndCoalescedSingle_shareOneChain() async {
        let fixture = await readyModel()
        let (model, socket) = (fixture.model, fixture.socket)
        await socket.setArtificialDelay(.milliseconds(80))

        model.send([("windlevel", .int(3))], to: model.devices[0])
        // Fires after the debounce, well after the batch above was enqueued.
        model.setValue(.int(5), forKey: "windlevel", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(500))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.value), [.int(3), .int(5)], "batch first, coalesced single after")
    }

    func test_twoDifferentDevices_deliverIndependently() async {
        let deviceA = DreoDevice(
            serialNumber: "A", deviceName: "Fan A", model: "DR-HPF008S",
            controlsConf: nil, state: ["poweron": .bool(true)]
        )
        let deviceB = DreoDevice(
            serialNumber: "B", deviceName: "Fan B", model: "DR-HPF008S",
            controlsConf: nil, state: ["poweron": .bool(true)]
        )
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success([deviceA, deviceB]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let socket = DreoSocketServiceFake()
        await socket.setArtificialDelay(.milliseconds(300))
        let model = AppModel(
            apiService: apiStub, socketService: socket,
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()

        let start = ContinuousClock.now
        model.setValue(.int(9), forKey: "windlevel", on: model.devices[0])
        model.setValue(.int(9), forKey: "windlevel", on: model.devices[1])
        try? await Task.sleep(for: .milliseconds(700))
        let elapsed = ContinuousClock.now - start

        let sent = await socket.sentCommands
        XCTAssertEqual(sent.count, 2, "one command per device")
        // One device's queue must not make the other wait behind it. Two
        // 300ms sends serialized would sum past 600ms; run in parallel they
        // land around 300ms plus scheduling noise. 900ms leaves comfortable
        // room for CI jitter while still catching a regression to serial.
        XCTAssertLessThan(elapsed, .milliseconds(900))
    }

    // MARK: - Failure handling

    func test_batchFailure_stopsTheBatchAndResyncsFromREST() async {
        let fixture = await readyModel()
        let (model, apiStub, socket) = (fixture.model, fixture.apiStub, fixture.socket)
        await socket.setFailOnceForKey("windlevel")
        await apiStub.setStateResult(.success(["windlevel": .int(1), "atmon": .bool(false)]))

        model.send([("windlevel", .int(9)), ("atmon", .bool(true))], to: model.devices[0])

        try? await Task.sleep(for: .milliseconds(300))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["windlevel"], "the command after the failure must not be sent")
        XCTAssertEqual(
            model.devices[0].state["atmon"], .bool(false),
            "resync must undo the optimistic write for the command that never reached the fan"
        )
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: - Lifecycle drain

    func test_removingADevice_stopsAPendingSendFromReachingTheSocket() async {
        let fixture = await readyModel()
        let (model, apiStub, socket) = (fixture.model, fixture.apiStub, fixture.socket)
        await apiStub.setRemoveResult(.success(()))
        let device = model.devices[0]

        model.setValue(.int(9), forKey: "windlevel", on: device)
        await model.removeDevice(device)

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertTrue(sent.isEmpty, "a command queued before removal must not fire after it")
        XCTAssertNil(model.errorMessage, "no error should surface for a device that is gone")
    }

    func test_signingOut_stopsAPendingSendFromReachingTheSocket() async {
        let fixture = await readyModel()
        let (model, socket) = (fixture.model, fixture.socket)

        model.setValue(.int(9), forKey: "windlevel", on: model.devices[0])
        await model.signOut()

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertTrue(sent.isEmpty, "a command queued before sign-out must not fire after it")
    }
}
