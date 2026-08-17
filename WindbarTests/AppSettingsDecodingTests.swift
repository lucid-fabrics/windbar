import XCTest
@testable import Windbar

/// Settings are one JSON blob in UserDefaults, and `SettingsRepository.load()`
/// answers a decode failure with `.default`. That makes every new field an
/// upgrade hazard: a field the stored JSON predates throws `keyNotFound`, the
/// throw is swallowed, and the user silently loses everything else in the blob.
///
/// This happened. Adding `presetsBySerialNumber` as a required key reset every
/// existing user's `hasCompletedOnboarding` to false, so the next time their
/// token expired they got the first-run wizard instead of the login screen.
final class AppSettingsDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func test_blobWrittenBeforePresetsExisted_stillLoads() throws {
        let settings = try decode("""
        {"lastSelectedDeviceSerialNumber":"SN1","hasCompletedOnboarding":true}
        """)

        XCTAssertEqual(settings.lastSelectedDeviceSerialNumber, "SN1")
        XCTAssertTrue(settings.hasCompletedOnboarding, "an upgrade must not re-run onboarding")
        XCTAssertEqual(settings.presetsBySerialNumber, [:])
    }

    /// The general rule, not just the one field that broke: any single key
    /// going missing must not take the rest of the blob down with it.
    func test_anyMissingKeyFallsBackWithoutLosingTheOthers() throws {
        XCTAssertTrue(try decode("""
        {"hasCompletedOnboarding":true,"presetsBySerialNumber":{}}
        """).hasCompletedOnboarding)

        XCTAssertEqual(try decode("""
        {"lastSelectedDeviceSerialNumber":"SN9"}
        """).lastSelectedDeviceSerialNumber, "SN9")

        XCTAssertEqual(try decode("{}"), .default)
    }

    func test_currentBlobRoundTrips() throws {
        let settings = AppSettings(
            lastSelectedDeviceSerialNumber: "SN1",
            hasCompletedOnboarding: true,
            presetsBySerialNumber: ["SN1": [DevicePreset(name: "North", values: ["windlevel": .int(9)])]]
        )

        let decoded = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(decoded, settings)
    }
}
