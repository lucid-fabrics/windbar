import XCTest
@testable import Windbar

/// The DR-HCF001S ceiling fan's lamp, reported missing in the wild. Its
/// `CFLight` section describes brightness and colour temperature as ranges
/// (`minValue`/`maxValue`, no `value`), which the old `ControlItem` decoder
/// treated as malformed, so the lossy schema decode silently dropped the
/// whole light while Speed and the fan modes survived.
@MainActor
final class CFLightTests: XCTestCase {
    /// The section shaped exactly as the server sends it for this model,
    /// copied from the captured device-list response in the hass-dreo
    /// project's test fixtures (tests/pydreo/api_responses).
    private static let serverJSON = Data("""
    {
      "control": [
        {
          "id": "110",
          "type": "Speed",
          "title": "device_control_speed",
          "items": [
            {"text": "1", "cmd": "windlevel", "value": 1},
            {"text": "12", "cmd": "windlevel", "value": 12}
          ]
        },
        {
          "id": "140",
          "type": "CFLight",
          "title": "device_control_light",
          "cmd": "lighton",
          "items": [
            {"type": "light", "text": "device_fans_mode_natural", "image": "ic_cf_light",
             "cmd": "brightness", "maxValue": 100, "minValue": 1},
            {"type": "color", "text": "device_control_mode_sleep", "image": "ic_color_bar",
             "cmd": "colortemp", "maxValue": 100, "minValue": 0}
          ]
        }
      ],
      "preference": []
    }
    """.utf8)

    private func decodedSchema() throws -> ControlSchema {
        try JSONDecoder().decode(ControlSchema.self, from: Self.serverJSON)
    }

    func test_lightSection_survivesDecoding() throws {
        let schema = try decodedSchema()

        XCTAssertEqual(schema.control.map(\.type), ["Speed", "CFLight"],
                       "the light section used to be dropped wholesale")
        let light = schema.control[1]
        XCTAssertEqual(light.cmd, "lighton")
        XCTAssertEqual(light.items?.count, 2)
    }

    func test_rangeItems_carryTheVendorsBounds() throws {
        let light = try decodedSchema().control[1]

        XCTAssertEqual(light.items?[0].cmd, "brightness")
        XCTAssertEqual(light.items?[0].range, 1...100)
        XCTAssertEqual(light.items?[1].cmd, "colortemp")
        XCTAssertEqual(light.items?[1].range, 0...100)
    }

    /// The vendor reuses unrelated mode strings in these items' `text`
    /// ("Natural" on a dimmer), so captions come from the kind tag instead.
    func test_rangeItems_labelBySliderKindNotByTheirBorrowedText() throws {
        let light = try decodedSchema().control[1]

        XCTAssertEqual(light.items?[0].rangeTitle, "Brightness")
        XCTAssertEqual(light.items?[1].rangeTitle, "Color Temperature")
    }

    func test_discreteItems_decodeExactlyAsBefore() throws {
        let speed = try decodedSchema().control[0]

        XCTAssertEqual(speed.items?.map(\.value), [.int(1), .int(12)])
        XCTAssertNil(speed.items?[0].range)
    }

    // MARK: - Implicit prerequisite

    private func ceilingFan(lighton: Bool) throws -> DreoDevice {
        DreoDevice(
            serialNumber: "SN-CF",
            deviceName: "Ceiling Fan",
            model: "DR-HCF001S",
            controlsConf: try decodedSchema(),
            state: [
                "connected": .bool(true),
                "poweron": .bool(true),
                "windlevel": .int(3),
                "lighton": .bool(lighton),
                "brightness": .int(40),
                "colortemp": .int(0)
            ]
        )
    }

    private func readyModel(device: DreoDevice) async -> AppModel {
        let apiStub = DreoAPIServiceStub()
        await apiStub.setDevicesResult(.success([device]))
        await apiStub.setSession(DreoSession(accessToken: "tok", regionHost: "us"))
        let model = AppModel(
            apiService: apiStub,
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(stored: DreoCredentials(email: "a@b.com", password: "x")),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        return model
    }

    /// The server never spells out that the dimmer needs the lamp on, unlike
    /// the hand-maintained overrides which say `requires` explicitly. A
    /// range item inside a section that has its own switch depends on that
    /// switch, so moving the dimmer with the lamp dark turns it on first.
    func test_dimmer_implicitlyRequiresTheLampsOwnSwitch() async throws {
        let model = await readyModel(device: try ceilingFan(lighton: false))

        XCTAssertEqual(model.requirement(forKey: "brightness", on: model.devices[0]), "lighton")
        XCTAssertEqual(model.requirement(forKey: "colortemp", on: model.devices[0]), "lighton")
    }

    /// The switch itself, and controls outside the section, gain nothing.
    func test_theSwitchAndUnrelatedControls_haveNoImplicitPrerequisite() async throws {
        let model = await readyModel(device: try ceilingFan(lighton: false))

        XCTAssertNil(model.requirement(forKey: "lighton", on: model.devices[0]))
        XCTAssertNil(model.requirement(forKey: "windlevel", on: model.devices[0]))
    }

    /// An explicit `requires` from an override still beats the inference.
    func test_explicitRequires_stillWins() async {
        let section = ControlSection(
            rawId: "300", type: "AmbientBrightness", title: "Light Brightness", cmd: "atmon",
            items: [ControlItem(text: "Low", cmd: "atmbri", value: .int(1), minValue: 1, maxValue: 3)],
            reverse: nil, trueValue: nil, falseValue: nil, requires: "someswitch"
        )
        let device = DreoDevice(
            serialNumber: "SN-X", deviceName: "Fan", model: "DR-HPF008S",
            controlsConf: ControlSchema(control: [section], preference: []),
            state: [:]
        )
        let model = await readyModel(device: device)

        XCTAssertEqual(model.requirement(forKey: "atmbri", on: model.devices[0]), "someswitch")
    }

    /// The diagnostics report drove this fix: `lighton`, `brightness` and
    /// `colortemp` sat in "Reported but not shown". With the section decoding
    /// they are schema commands now and drop out of that list on their own.
    /// The URL trigger's relative nudge used to scan discrete item values
    /// for bounds; a range control is one item, so min == max and the nudge
    /// silently did nothing while the slider worked.
    func test_adjustValue_walksARangeControl() async throws {
        let model = await readyModel(device: try ceilingFan(lighton: true))

        model.adjustValue(forKey: "brightness", by: 10, onSerialNumber: "SN-CF")
        XCTAssertEqual(model.devices[0].state["brightness"], .int(50))

        model.adjustValue(forKey: "brightness", by: 100, onSerialNumber: "SN-CF")
        XCTAssertEqual(model.devices[0].state["brightness"], .int(100),
                       "a nudge past the top must clamp to the vendor's maximum")
    }

    /// An item with neither `value` nor bounds is malformed; it must drop
    /// its section the way it always did, not become a chip sending 0.
    func test_itemWithNeitherValueNorBounds_dropsItsSection() throws {
        let json = Data("""
        {
          "control": [
            {"id": "1", "type": "Speed", "title": "Speed",
             "items": [{"text": "1", "cmd": "windlevel", "value": 1},
                       {"text": "9", "cmd": "windlevel", "value": 9}]},
            {"id": "2", "type": "Broken", "title": "Broken",
             "items": [{"text": "??", "cmd": "mystery"}]}
          ],
          "preference": []
        }
        """.utf8)

        let schema = try JSONDecoder().decode(ControlSchema.self, from: json)

        XCTAssertEqual(schema.control.map(\.type), ["Speed"])
    }

    func test_diagnosticsReport_noLongerFlagsTheLightAsUnshown() throws {
        let unmapped = DeviceDiagnostics.unmappedKeys(for: try ceilingFan(lighton: false))

        for key in ["lighton", "brightness", "colortemp"] {
            XCTAssertFalse(unmapped.contains(key), "\(key) still reported as an unshown control")
        }
    }
}
