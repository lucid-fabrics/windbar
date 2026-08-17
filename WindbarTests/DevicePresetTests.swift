import XCTest
@testable import Windbar

@MainActor
final class DevicePresetTests: XCTestCase {
    private func deviceWithState() -> DreoDevice {
        DreoDevice(
            serialNumber: "SN1",
            deviceName: "Tower Fan",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: [
                "poweron": .bool(true),
                "windlevel": .int(12),
                "hoscangle": .string("-45,45")
            ]
        )
    }

    private func readyModel(devices: [DreoDevice]) async -> (AppModel, DreoSocketServiceFake) {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success(devices))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let socketFake = DreoSocketServiceFake()
        let model = AppModel(
            apiService: apiStub,
            socketService: socketFake,
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        return (model, socketFake)
    }

    /// Phase 2 of the audit remediation. Sorting a preset's keys alphabetically
    /// sent three of the light's four controls before the switch that makes
    /// any of them do anything: atmbri < atmcolor < atmmode < atmon. Order
    /// now comes from the device's own schema, prerequisite before dependent.
    func test_applyPreset_ordersKeysBySchemaWithPrerequisitesFirst() async {
        let schema = ControlSchema(
            control: [
                ControlSection(
                    rawId: "310", type: "AmbientEffect", title: "Light Effect", cmd: nil,
                    items: [ControlItem(text: "Breath", cmd: "atmmode", value: .int(2))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: "atmon"
                ),
                ControlSection(
                    rawId: "295", type: "Toggle", title: "Ambient Light", cmd: "atmon",
                    items: nil, reverse: false, trueValue: nil, falseValue: nil, requires: nil
                ),
                ControlSection(
                    rawId: "300", type: "AmbientBrightness", title: "Light Brightness", cmd: nil,
                    items: [ControlItem(text: "High", cmd: "atmbri", value: .int(3))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: "atmon"
                )
            ],
            preference: []
        )
        let device = DreoDevice(
            serialNumber: "SN1", deviceName: "Air Circulator", model: "DR-HPF008S",
            controlsConf: schema, state: ["poweron": .bool(true)]
        )
        let (model, socketFake) = await readyModel(devices: [device])
        let preset = DevicePreset(
            name: "Warm Glow",
            values: ["atmbri": .int(3), "atmmode": .int(2), "atmon": .bool(true)]
        )

        model.apply(preset: preset, on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        // atmon precedes both atmmode and atmbri regardless of the schema
        // listing the effect section before the toggle, and regardless of
        // alphabetical order (atmbri would otherwise sort before atmon).
        XCTAssertEqual(sent.map(\.key), ["poweron", "atmon", "atmmode", "atmbri"])
    }

    func test_applyPreset_sendsPowerFirstThenTheShape() async {
        let (model, socketFake) = await readyModel(devices: [deviceWithState()])
        let preset = DevicePreset(name: "Direction North", values: [
            "windlevel": .int(12),
            "hoscangle": .string("-45,45")
        ])

        model.apply(preset: preset, on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        XCTAssertEqual(sent.map(\.key), ["poweron", "hoscangle", "windlevel"])
        XCTAssertEqual(sent.first?.value, .bool(true))
    }

    /// A preset saved before power was excluded still carries `poweron`, and
    /// it must not be able to send an "off" in the middle of an apply.
    func test_applyPreset_ignoresAStoredPowerValue() async {
        let (model, socketFake) = await readyModel(devices: [deviceWithState()])
        let legacy = DevicePreset(name: "Legacy", values: [
            "poweron": .bool(false),
            "windlevel": .int(4)
        ])

        model.apply(preset: legacy, on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        XCTAssertEqual(sent.map(\.key), ["poweron", "windlevel"])
        XCTAssertEqual(sent.first?.value, .bool(true))
    }

    func test_firePreset_byId_runsIt() async {
        let (model, socketFake) = await readyModel(devices: [deviceWithState()])
        let preset = DevicePreset(name: "Breathe All Room", values: ["windlevel": .int(8)])
        model.savePreset(preset, on: model.devices[0])

        model.firePreset(id: preset.id, onSerialNumber: "SN1")

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        XCTAssertTrue(sent.contains(where: { $0.key == "windlevel" && $0.value == .int(8) }))
    }

    func test_firePreset_whenAlreadyRunningIt_turnsTheFanOff() async {
        let (model, socketFake) = await readyModel(devices: [deviceWithState()])
        // The device already sits at windlevel 12, so this preset is active.
        let preset = DevicePreset(name: "Direction North", values: ["windlevel": .int(12)])
        model.savePreset(preset, on: model.devices[0])
        XCTAssertTrue(model.isActive(preset, on: model.devices[0]))

        model.fire(preset, on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        XCTAssertEqual(sent.map(\.key), ["poweron"])
        XCTAssertEqual(sent.first?.value, .bool(false))
        XCTAssertFalse(model.devices[0].isOn)
    }

    func test_firePreset_whenAnotherIsActive_switchesWithoutTurningOff() async {
        let (model, socketFake) = await readyModel(devices: [deviceWithState()])
        let north = DevicePreset(name: "North", values: ["windlevel": .int(12)])
        let breathe = DevicePreset(name: "Breathe", values: ["windlevel": .int(4)])
        model.savePreset(north, on: model.devices[0])
        model.savePreset(breathe, on: model.devices[0])

        model.fire(breathe, on: model.devices[0])

        try? await Task.sleep(for: .milliseconds(400))
        let sent = await socketFake.sentCommands
        XCTAssertFalse(sent.contains(where: { $0.key == "poweron" && $0.value == .bool(false) }))
        XCTAssertTrue(model.devices[0].isOn)
        XCTAssertTrue(model.isActive(breathe, on: model.devices[0]))
        XCTAssertFalse(model.isActive(north, on: model.devices[0]))
    }

    func test_isActive_isFalseWhenTheFanIsOff() async {
        var device = deviceWithState()
        device.state["poweron"] = .bool(false)
        let (model, _) = await readyModel(devices: [device])
        let preset = DevicePreset(name: "North", values: ["windlevel": .int(12)])

        XCTAssertFalse(model.isActive(preset, on: model.devices[0]))
    }

    func test_isActive_isFalseAfterAValueDrifts() async {
        let (model, _) = await readyModel(devices: [deviceWithState()])
        let preset = DevicePreset(name: "North", values: ["windlevel": .int(12)])
        XCTAssertTrue(model.isActive(preset, on: model.devices[0]))

        model.setValue(.int(3), forKey: "windlevel", on: model.devices[0])

        XCTAssertFalse(model.isActive(preset, on: model.devices[0]))
    }

    func test_savePreset_stripsPowerFromTheStoredShape() {
        let model = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )
        let device = deviceWithState()

        model.savePreset(
            DevicePreset(name: "North", values: ["poweron": .bool(true), "windlevel": .int(12)]),
            on: device
        )

        let stored = model.settings.presetsBySerialNumber["SN1"]?.first
        XCTAssertNil(stored?.values["poweron"])
        XCTAssertEqual(stored?.values["windlevel"], .int(12))
    }

    func test_saveAndRemovePreset_mutatesSettings() {
        let model = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )
        let device = deviceWithState()
        let preset = DevicePreset(name: "North", values: ["windlevel": .int(12)])

        model.savePreset(preset, on: device)
        XCTAssertEqual(model.settings.presetsBySerialNumber["SN1"]?.count, 1)

        model.removePreset(id: preset.id, on: device)
        XCTAssertEqual(model.settings.presetsBySerialNumber["SN1"]?.count, 0)
    }

    func test_savePreset_withExistingId_updatesInPlace() {
        let model = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )
        let device = deviceWithState()
        let original = DevicePreset(name: "Direction North", values: ["windlevel": .int(8)])
        let edited = DevicePreset(id: original.id, name: "Direction South", values: ["windlevel": .int(12)])

        model.savePreset(original, on: device)
        model.savePreset(edited, on: device)

        let list = model.settings.presetsBySerialNumber["SN1"] ?? []
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, original.id)
        XCTAssertEqual(list.first?.name, "Direction South")
        XCTAssertEqual(list.first?.values["windlevel"], .int(12))
    }

    func test_savePreset_withNewId_appends() {
        let model = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )
        let device = deviceWithState()

        model.savePreset(DevicePreset(name: "North", values: ["windlevel": .int(8)]), on: device)
        model.savePreset(DevicePreset(name: "South", values: ["windlevel": .int(12)]), on: device)

        XCTAssertEqual(model.settings.presetsBySerialNumber["SN1"]?.count, 2)
    }
}
