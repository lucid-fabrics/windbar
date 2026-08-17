import XCTest
@testable import Windbar

/// Phase 4 of the audit remediation. Redaction was substring-based on very
/// short fragments (`sn`, `ip`, `mac`, `key`, `name`), which cut both ways:
/// `serialnumber` has no `sn` substring and slipped through unredacted, while
/// `ip` matched inside `chipid`/`chipversion` and hid exactly the diagnostic
/// this report exists to surface. These pin the corrected list.
final class DeviceDiagnosticsTests: XCTestCase {
    func test_redacts_theDeviceSerialKeyThatTriggeredThisFeature() {
        XCTAssertTrue(DeviceDiagnostics.isRedacted("devicesn"))
    }

    func test_redacts_wholeWordsAShortFragmentUsedToMiss() {
        XCTAssertTrue(DeviceDiagnostics.isRedacted("serialNumber"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("macAddress"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("ipAddress"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("timezone"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("latitude"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("longitude"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("city"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("country"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("accountId"))
        XCTAssertTrue(DeviceDiagnostics.isRedacted("userId"))
    }

    /// The concrete collateral the old short fragment caused: "ip" inside
    /// "chipid" hid a real hardware diagnostic key for no privacy reason.
    func test_doesNotRedact_diagnosticKeysThatMerelyContainAShortFragment() {
        XCTAssertFalse(DeviceDiagnostics.isRedacted("chipid"))
        XCTAssertFalse(DeviceDiagnostics.isRedacted("chipversion"))
        XCTAssertFalse(DeviceDiagnostics.isRedacted("mcu_hardware_model"))
    }

    func test_doesNotRedact_ordinaryControlKeys() {
        for key in ["windlevel", "oscmode", "atmcolor", "atmbri", "temperature", "poweron"] {
            XCTAssertFalse(DeviceDiagnostics.isRedacted(key), "\(key) is a real control, not identifying data")
        }
    }

    func test_report_neverPrintsARedactedKeysValue() {
        let device = DreoDevice(
            serialNumber: "SN1", deviceName: "Fan", model: "DR-HPF008S",
            controlsConf: nil,
            state: ["devicesn": .string("SECRET-SERIAL-VALUE"), "windlevel": .int(5)]
        )

        let report = DeviceDiagnostics.report(for: device, appVersion: "1.0")

        XCTAssertFalse(report.contains("SECRET-SERIAL-VALUE"))
        XCTAssertFalse(report.contains("devicesn"))
        XCTAssertTrue(report.contains("windlevel"))
    }
}
