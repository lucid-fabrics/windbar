import XCTest
@testable import Windbar

/// Regression cover for a slider drag. Every step used to go to the wire, and
/// the resulting commands raced: one lost its ack to a sibling, timed out,
/// then retried a value the user had already dragged past, which the fan
/// refused. The user saw a failure on a control they never set to that value.
@MainActor
final class ControlCoalescingTests: XCTestCase {
    private func readyModel() async -> (AppModel, DreoSocketServiceFake) {
        let apiStub = DreoAPIServiceStub()
        let device = DreoDevice(
            serialNumber: "SN1",
            deviceName: "Air Circulator",
            model: "DR-HPF008S",
            controlsConf: nil,
            state: ["poweron": .bool(true), "atmspeed": .int(1)]
        )
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
        return (model, socket)
    }

    /// The fan accepts a colour while its light ring is off, reports that it
    /// applied it, and stays dark. Nothing fails, so nothing can be reported,
    /// and the control just looks broken. Using it has to switch the ring on.
    func test_settingALightControl_switchesTheLightOnFirst() async {
        let (model, socket) = await lightModel(isLightOn: false)

        model.setValue(.int(0xFF0000), forKey: "atmcolor", on: model.devices[0])

        await model.settleDeliveries(forSerialNumber: model.devices[0].serialNumber)
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["atmon", "atmcolor"])
        XCTAssertEqual(sent.first?.value, .bool(true))
    }

    func test_settingALightControl_leavesAnAlreadyLitRingAlone() async {
        let (model, socket) = await lightModel(isLightOn: true)

        model.setValue(.int(0xFF0000), forKey: "atmcolor", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["atmcolor"])
    }

    /// Only controls whose schema declares a prerequisite get one.
    func test_ordinaryControlsAreNotGivenAPrerequisite() async {
        let (model, socket) = await lightModel(isLightOn: false)

        model.setValue(.int(5), forKey: "windlevel", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["windlevel"])
    }

    private func lightModel(isLightOn: Bool) async -> (AppModel, DreoSocketServiceFake) {
        let schema = ControlSchema(
            control: [
                ControlSection(
                    rawId: "295", type: "Toggle", title: "Ambient Light", cmd: "atmon",
                    items: nil, reverse: false, trueValue: nil, falseValue: nil, requires: nil
                ),
                ControlSection(
                    rawId: "315", type: "Color", title: "Light Colour", cmd: nil,
                    items: [ControlItem(text: "Red", cmd: "atmcolor", value: .int(0xFF0000))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: "atmon"
                ),
                ControlSection(
                    rawId: "110", type: "Speed", title: "Speed", cmd: nil,
                    items: [ControlItem(text: "5", cmd: "windlevel", value: .int(5))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: nil
                )
            ],
            preference: []
        )
        let device = DreoDevice(
            serialNumber: "SN1",
            deviceName: "Air Circulator",
            model: "DR-HPF008S",
            controlsConf: schema,
            state: ["poweron": .bool(true), "atmon": .bool(isLightOn)]
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
        return (model, socket)
    }

    /// Regression: a control with a prerequisite must coalesce like any
    /// other. Sending the prerequisite immediately exempted those controls
    /// from coalescing entirely, and the light's own speed slider has one, so
    /// dragging it with the ring off sent five redundant switch-ons racing
    /// five values, which is the exact flood coalescing exists to prevent.
    func test_repeatedChangesToAControlWithAPrerequisite_stillCoalesce() async {
        let (model, socket) = await lightModel(isLightOn: false)
        // A stale copy, the way a live drag gesture holds the device value it
        // captured when the gesture began.
        let asCapturedAtDragStart = model.devices[0]

        for step in 2...6 {
            model.setValue(.int(step), forKey: "atmcolor", on: asCapturedAtDragStart)
        }

        await model.settleDeliveries(forSerialNumber: model.devices[0].serialNumber)
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["atmon", "atmcolor"], "one switch-on, one value")
        XCTAssertEqual(sent.last?.value, .int(6), "and it is the value the drag ended on")
    }

    func test_draggingAControl_sendsOnlyTheValueItSettledOn() async {
        let (model, socket) = await readyModel()

        for step in 2...6 {
            model.setValue(.int(step), forKey: "atmspeed", on: model.devices[0])
        }

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.filter { $0.key == "atmspeed" }.count, 1)
        XCTAssertEqual(sent.last?.value, .int(6))
    }

    /// The UI must not wait for the wire, or a drag would feel dead.
    func test_localStateTracksEveryStepImmediately() async {
        let (model, _) = await readyModel()

        model.setValue(.int(4), forKey: "atmspeed", on: model.devices[0])

        XCTAssertEqual(model.devices[0].state["atmspeed"], .int(4))
    }

    /// Two different controls are not the same control, so neither should
    /// swallow the other.
    func test_differentControlsAreNotCoalescedTogether() async {
        let (model, socket) = await readyModel()

        model.setValue(.int(3), forKey: "atmspeed", on: model.devices[0])
        model.setValue(.int(2), forKey: "atmbri", on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertEqual(Set(sent.map(\.key)), ["atmspeed", "atmbri"])
    }

    /// A preset is one deliberate action and must arrive whole and in order,
    /// so it is delivered rather than coalesced.
    func test_batchSendIsNotDelayedOrCoalesced() async {
        let (model, socket) = await readyModel()

        model.send([("poweron", .bool(true)), ("atmspeed", .int(5))], to: model.devices[0])

        try? await Task.sleep(for: .milliseconds(120))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.map(\.key), ["poweron", "atmspeed"])
    }

    /// A pending single send for a key the batch also sets would land after
    /// the batch and quietly undo it.
    func test_batchSendCancelsAPendingSendForTheSameControl() async {
        let (model, socket) = await readyModel()

        model.setValue(.int(9), forKey: "atmspeed", on: model.devices[0])
        model.send([("atmspeed", .int(2))], to: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socket.sentCommands
        XCTAssertEqual(sent.filter { $0.key == "atmspeed" }.map(\.value), [.int(2)])
    }
}
