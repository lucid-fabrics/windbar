import XCTest
@testable import Windbar

/// The fan sends Fahrenheit. Everything here is about what the user is shown.
final class TemperatureUnitTests: XCTestCase {

    func test_fahrenheit_showsTheFanReadingUnchanged() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.format(fahrenheit: 74), "74°F")
    }

    func test_celsius_convertsFromTheFahrenheitTheFanSends() {
        // 74°F is 23.33°C, and the reading is shown as whole degrees.
        XCTAssertEqual(TemperatureUnit.celsius.format(fahrenheit: 74), "23°C")
        // 32°F is the freezing point, the one value both scales agree on.
        XCTAssertEqual(TemperatureUnit.celsius.format(fahrenheit: 32), "0°C")
    }

    /// Rounds rather than truncates. 71°F is 21.67°C, which truncation would
    /// show as 21° and put the reading a degree below the room.
    func test_celsius_roundsRatherThanTruncating() {
        XCTAssertEqual(TemperatureUnit.celsius.format(fahrenheit: 71), "22°C")
    }

    /// Below freezing the two disagree in sign, and truncating toward zero
    /// would round the wrong way. 20°F is -6.67°C, not -6°C.
    func test_celsius_roundsCorrectlyBelowZero() {
        XCTAssertEqual(TemperatureUnit.celsius.format(fahrenheit: 20), "-7°C")
    }

    /// The unit is always written out. "23°" alone next to a middot reads as
    /// Fahrenheit to an American and Celsius to everyone else, which is the
    /// ambiguity this whole preference exists to remove.
    func test_everyUnitNamesItself() {
        for unit in TemperatureUnit.allCases {
            let shown = unit.format(fahrenheit: 74)
            XCTAssertTrue(shown.hasSuffix("C") || shown.hasSuffix("F"),
                          "\(unit) rendered \(shown) without naming a scale")
        }
    }

    /// Old settings blobs predate this key and must still load. Getting this
    /// wrong once already reset every user's presets and onboarding flag.
    func test_settingsWithoutTheKeyStillDecode() throws {
        let json = Data(#"{"hasCompletedOnboarding":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.temperatureUnit, .automatic)
        XCTAssertTrue(settings.hasCompletedOnboarding)
    }

    func test_theChoiceSurvivesASaveAndLoad() throws {
        var settings = AppSettings.default
        settings.temperatureUnit = .celsius
        let restored = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.temperatureUnit, .celsius)
    }
}
