import XCTest
@testable import Windbar

final class DreoDeviceWaterStateTests: XCTestCase {
    private func device(_ state: [String: DreoValue]) -> DreoDevice {
        DreoDevice(serialNumber: "SN", deviceName: "Fan", model: "DR-HEC005S", controlsConf: nil, state: state)
    }

    func test_isMisting_needsThePumpAndThePower() {
        XCTAssertTrue(device(["poweron": .bool(true), "miston": .bool(true)]).isMisting)
        // The pump flag survives power-off, but a stopped fan is not misting.
        XCTAssertFalse(device(["poweron": .bool(false), "miston": .bool(true)]).isMisting)
        XCTAssertFalse(device(["poweron": .bool(true), "miston": .bool(false)]).isMisting)
    }

    func test_waterTankEmpty_onlyOnMistingModels() {
        XCTAssertTrue(device(["miston": .bool(false), "wrong": .int(1)]).isWaterTankEmpty)
        XCTAssertFalse(device(["miston": .bool(true), "wrong": .int(0)]).isWaterTankEmpty)
        // A plain fan reporting `wrong` means something else; never call it a tank.
        XCTAssertFalse(device(["wrong": .int(1)]).isWaterTankEmpty)
    }

    func test_humidity_readsTheSensorWhenPresent() {
        XCTAssertEqual(device(["rh": .int(60)]).humidity, 60)
        XCTAssertNil(device([:]).humidity)
    }
}
