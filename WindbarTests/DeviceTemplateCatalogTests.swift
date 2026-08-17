import XCTest
@testable import Windbar

final class DeviceTemplateCatalogTests: XCTestCase {
    func test_catalog_loadsBundledTemplates() {
        XCTAssertGreaterThan(DeviceTemplateCatalog.modelCount, 50)
    }

    func test_catalog_hasSchemaForModelTheServerDoesNotDescribe() throws {
        // DR-HPF008S is the case that motivated this: the API returns only
        // {"template": "DR-HPF008S"} for it.
        let schema = try XCTUnwrap(DeviceTemplateCatalog.schema(forModel: "DR-HPF008S"))

        let speed = try XCTUnwrap(schema.control.first { $0.type == "Speed" })
        let levels = (speed.items ?? []).compactMap(\.value.intValue)
        XCTAssertEqual(levels.min(), 1)
        XCTAssertEqual(levels.max(), 9)

        // Turbo comes from the overrides layer, appended to the four modes
        // the vendor config ships.
        let mode = try XCTUnwrap(schema.control.first { $0.type == "Mode" })
        XCTAssertEqual((mode.items ?? []).map(\.text), ["Normal", "Auto", "Sleep", "Natural", "Turbo"])
        XCTAssertEqual((mode.items ?? []).compactMap(\.value.intValue), [1, 4, 3, 2, 5])

        // Panel Sound is reported inverted: muteon == true means sound off.
        let panelSound = try XCTUnwrap(schema.preference.first { $0.cmd == "muteon" })
        XCTAssertEqual(panelSound.reverse, true)
    }

    func test_catalog_returnsNilForUnknownModel() {
        XCTAssertNil(DeviceTemplateCatalog.schema(forModel: "DR-NOT-A-REAL-MODEL"))
    }

    func test_overrides_addASectionTheVendorConfigOmits() throws {
        // The 508S has horizontal and vertical movement, which the vendor
        // config describes for no PolyFan at all. The fan accepts 0-4 and
        // answers 5 with a validation error, so the range is the hardware's,
        // not a guess.
        let schema = try XCTUnwrap(DeviceTemplateCatalog.schema(forModel: "DR-HPF008S"))
        let oscillation = try XCTUnwrap(schema.control.first { $0.title == "Oscillation" })

        XCTAssertEqual(Set((oscillation.items ?? []).map(\.cmd)), ["oscmode"])
        XCTAssertEqual((oscillation.items ?? []).compactMap(\.value.intValue), [0, 1, 2, 3, 4])
    }

    /// Every ambient-light range below was mapped by probing the fan until it
    /// refused a value, so a drift here means someone widened a range without
    /// checking it against hardware.
    func test_overrides_addAmbientLightWithinTheRangesTheFanAccepts() throws {
        let schema = try XCTUnwrap(DeviceTemplateCatalog.schema(forModel: "DR-HPF008S"))

        let brightness = try XCTUnwrap(schema.control.first { $0.title == "Light Brightness" })
        XCTAssertEqual((brightness.items ?? []).compactMap(\.value.intValue), [1, 2, 3])

        let effect = try XCTUnwrap(schema.control.first { $0.title == "Light Effect" })
        XCTAssertEqual((effect.items ?? []).compactMap(\.value.intValue), [1, 2, 3])

        // 1-3, not 1-9. The fan refuses 4 and above; an earlier reading of 9
        // came from a probe whose detection window caught a neighbouring
        // command's reply, and it shipped a slider whose top two thirds were
        // all refusals.
        let speed = try XCTUnwrap(schema.control.first { $0.title == "Light Speed" })
        XCTAssertEqual((speed.items ?? []).compactMap(\.value.intValue), [1, 2, 3])

        let display = try XCTUnwrap(schema.control.first { $0.title == "Display" })
        XCTAssertEqual((display.items ?? []).compactMap(\.value.intValue), [0, 1, 2])

        // The light's own switch sits with the controls it governs. Behind
        // "More options" nothing on screen said the ring was off, so the
        // colour and brightness rows looked broken rather than inert.
        let ambient = try XCTUnwrap(schema.control.first { $0.cmd == "atmon" })
        XCTAssertEqual(ambient.type, "Toggle")
        XCTAssertEqual(ambient.reverse, false)
        XCTAssertNil(schema.preference.first { $0.cmd == "atmon" })

        // And every control it governs says so, so using one switches it on.
        for section in [brightness, effect, speed] {
            XCTAssertEqual(section.requires, "atmon", "\(section.title ?? "?") lost its prerequisite")
        }
        let colors = try XCTUnwrap(schema.control.first { $0.type == "Color" })
        XCTAssertEqual(colors.requires, "atmon")
    }

    func test_overrides_documentationKeysAreNotModels() {
        XCTAssertNil(DeviceTemplateCatalog.schema(forModel: "_readme"))
    }

    func test_overrides_areAdditiveAndNeverDropAnExistingControl() {
        let base = ControlSchema(
            control: [
                ControlSection(
                    rawId: "100", type: "Mode", title: "Mode", cmd: nil,
                    items: [ControlItem(text: "Normal", cmd: "mode", value: .int(1))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: nil
                )
            ],
            preference: []
        )
        let override = ControlSchema(
            control: [
                ControlSection(
                    rawId: "100", type: "Mode", title: "Mode", cmd: nil,
                    items: [ControlItem(text: "Turbo", cmd: "mode", value: .int(5))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: nil
                ),
                ControlSection(
                    rawId: "120", type: "OscillationMode", title: "Oscillation", cmd: nil,
                    items: [ControlItem(text: "Off", cmd: "oscmode", value: .int(0))],
                    reverse: nil, trueValue: nil, falseValue: nil, requires: nil
                )
            ],
            preference: []
        )

        let merged = DeviceTemplateCatalog.apply(override, to: base)

        XCTAssertEqual(merged.control.count, 2)
        XCTAssertEqual(merged.control[0].items?.map(\.text), ["Normal", "Turbo"])
        XCTAssertEqual(merged.control[1].title, "Oscillation")
    }

    /// Phase 4 of the audit remediation. An override's items are always
    /// concatenated onto the base template's, never replacing them, so an
    /// override restating a value the base already has (say, correcting a
    /// label) used to leave two `ControlItem`s sharing the same
    /// `cmd_value` id in the same `ForEach`, which SwiftUI does not define
    /// behaviour for. The override's version has to win, since restating a
    /// value is how a correction is expressed at all.
    func test_dedupedItems_lastWriteWinsAtTheFirstPosition() {
        let items = [
            ControlItem(text: "Wrong Label", cmd: "mode", value: .int(1)),
            ControlItem(text: "Other", cmd: "mode", value: .int(2)),
            ControlItem(text: "Corrected Label", cmd: "mode", value: .int(1))
        ]

        let deduped = DeviceTemplateCatalog.dedupedItems(items)

        XCTAssertEqual(deduped.map(\.text), ["Corrected Label", "Other"], "position of first, text of last")
        XCTAssertEqual(Set(deduped.map(\.id)).count, deduped.count, "no id appears twice")
    }

    func test_catalog_everyControlSectionHasSelectableItems() throws {
        // A section with no items would render as an empty header, so the
        // generator drops those. Guard against that regressing. A Toggle is
        // the exception: it is the switch itself, so it has nothing to list.
        for model in ["DR-HPF008S", "DR-HTF004S"] {
            let schema = try XCTUnwrap(DeviceTemplateCatalog.schema(forModel: model))
            for section in schema.control where section.type != "Toggle" {
                XCTAssertFalse(section.items?.isEmpty ?? true, "\(model)/\(section.type) has no items")
            }
            for section in schema.control where section.type == "Toggle" {
                XCTAssertNotNil(section.cmd, "\(model) toggle has nothing to set")
            }
        }
    }
}
