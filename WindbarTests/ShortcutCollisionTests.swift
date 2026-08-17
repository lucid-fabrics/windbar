import KeyboardShortcuts
import XCTest
@testable import Windbar

@MainActor
final class ShortcutCollisionTests: XCTestCase {
    func test_registry_includesPowerAndAllPresetNames() {
        let device1 = DreoDevice(serialNumber: "SN1", deviceName: "Fan 1", model: "X", controlsConf: nil)
        let device2 = DreoDevice(serialNumber: "SN2", deviceName: "Fan 2", model: "X", controlsConf: nil)
        let presetA = DevicePreset(name: "A", values: [:])
        let presetB = DevicePreset(name: "B", values: [:])
        let names = ShortcutRegistry.names(
            devices: [device1, device2],
            presetsBySerialNumber: ["SN1": [presetA], "SN2": [presetB]]
        )

        let raws = names.map(\.rawValue)
        XCTAssertTrue(raws.contains(KeyboardShortcuts.Name.toggleFanPower.rawValue))
        XCTAssertTrue(raws.contains("togglePower.SN1"))
        XCTAssertTrue(raws.contains("togglePower.SN2"))
        XCTAssertTrue(raws.contains("preset.\(presetA.id.uuidString)"))
        XCTAssertTrue(raws.contains("preset.\(presetB.id.uuidString)"))
    }

    /// Phase 2 of the audit remediation. Presets are deliberately kept in
    /// settings across a sign-out, so `presetsBySerialNumber` can carry an
    /// entry for a serial that belongs to a different account than the one
    /// now signed in. That entry used to count as a live collision, so a new
    /// shortcut could be refused as "conflicting" with a preset the current
    /// account cannot see, cannot delete, and has no device for.
    func test_registry_excludesPresetsForADeviceNotCurrentlyLoaded() {
        let loaded = DreoDevice(serialNumber: "SN1", deviceName: "Fan 1", model: "X", controlsConf: nil)
        let visiblePreset = DevicePreset(name: "Visible", values: [:])
        let orphanedPreset = DevicePreset(name: "From a different account", values: [:])

        let names = ShortcutRegistry.names(
            devices: [loaded],
            presetsBySerialNumber: [
                "SN1": [visiblePreset],
                "SN-FROM-ANOTHER-ACCOUNT": [orphanedPreset]
            ]
        )

        let raws = names.map(\.rawValue)
        XCTAssertTrue(raws.contains("preset.\(visiblePreset.id.uuidString)"))
        XCTAssertFalse(raws.contains("preset.\(orphanedPreset.id.uuidString)"))
        XCTAssertFalse(raws.contains("togglePower.SN-FROM-ANOTHER-ACCOUNT"))
    }

    func test_displayDescription_labelsKnownShapes() {
        XCTAssertEqual(
            KeyboardShortcuts.Name.toggleFanPower.displayDescription,
            "Power (last used fan)"
        )
        XCTAssertTrue(
            KeyboardShortcuts.Name.togglePower(deviceSerialNumber: "SN1")
                .displayDescription.contains("Power")
        )
    }
}
