import KeyboardShortcuts
import XCTest
@testable import Windbar

@MainActor
final class DeviceShortcutBinderTests: XCTestCase {
    private func device(_ serialNumber: String) -> DreoDevice {
        DreoDevice(
            serialNumber: serialNumber,
            deviceName: "Fan \(serialNumber)",
            model: "DR-HTF004S",
            controlsConf: nil,
            state: ["connected": .bool(true)]
        )
    }

    func test_bind_registersEachDeviceOnce() {
        let binder = DeviceShortcutBinder()

        binder.bind(devices: [device("SN1"), device("SN2")]) { _ in }
        XCTAssertEqual(binder.boundCount, 2)

        // Refreshing the device list must not attach a second handler to the
        // same shortcut: two handlers would toggle the fan on and straight
        // back off on a single keypress.
        binder.bind(devices: [device("SN1"), device("SN2")]) { _ in }
        XCTAssertEqual(binder.boundCount, 2)
    }

    func test_bind_picksUpDevicesAddedLater() {
        let binder = DeviceShortcutBinder()

        binder.bind(devices: [device("SN1")]) { _ in }
        binder.bind(devices: [device("SN1"), device("SN2")]) { _ in }

        XCTAssertEqual(binder.boundCount, 2)
    }

    func test_shortcutNameIsStableAndUniquePerDevice() {
        let first = KeyboardShortcutsNameProbe.rawName(for: "SN1")
        let second = KeyboardShortcutsNameProbe.rawName(for: "SN2")

        // The serial is baked into the name, which is what keeps a fan's key
        // bound across launches.
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, KeyboardShortcutsNameProbe.rawName(for: "SN1"))
        XCTAssertTrue(first.contains("SN1"))
    }

    func test_bindPresets_registersEachPresetOnce() {
        let binder = DeviceShortcutBinder()
        let first = DevicePreset(name: "North", values: [:])
        let second = DevicePreset(name: "Breathe", values: [:])

        binder.bindPresets([first, second]) { _ in }
        binder.bindPresets([first, second]) { _ in }

        XCTAssertEqual(binder.boundCount, 2)
    }
}

private enum KeyboardShortcutsNameProbe {
    static func rawName(for serialNumber: String) -> String {
        KeyboardShortcuts.Name.togglePower(deviceSerialNumber: serialNumber).rawValue
    }
}
