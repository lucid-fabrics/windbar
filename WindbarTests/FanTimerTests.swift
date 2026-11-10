import XCTest
@testable import Windbar

final class FanTimerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func timer(du minutes: Int, ts stamp: Int) -> DreoValue {
        .object(["du": .int(minutes), "ts": .int(stamp)])
    }

    func test_command_stampsNowAndClampsToTheFansCeiling() {
        let command = FanTimer.command(.turnOff, minutes: 2000, now: now)
        XCTAssertEqual(command.key, "timeroff")
        XCTAssertEqual(command.value, .object(["ts": .int(1_800_000_000), "du": .int(719)]))

        XCTAssertEqual(FanTimer.command(.turnOn, minutes: -5, now: now).value,
                       .object(["ts": .int(1_800_000_000), "du": .int(0)]))
    }

    /// The payload hass-dreo sends, byte for byte in shape: `params` holds
    /// the object itself, not a string of it.
    func test_command_encodesAsANestedObjectOnTheWire() throws {
        let command = FanTimer.command(.turnOff, minutes: 60, now: now)
        let text = try DreoSocketService.encodeCommand(serialNumber: "SN", key: command.key, value: command.value)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let params = try XCTUnwrap(json["params"] as? [String: Any])
        let payload = try XCTUnwrap(params["timeroff"] as? [String: Int])
        XCTAssertEqual(payload, ["du": 60, "ts": 1_800_000_000])
    }

    func test_active_endsDurationAfterTheStamp() {
        let started = 1_800_000_000 - 600
        let running = FanTimer.active(in: ["timeroff": timer(du: 30, ts: started)], now: now)
        XCTAssertEqual(running?.kind, .turnOff)
        XCTAssertEqual(running?.endsAt, Date(timeIntervalSince1970: TimeInterval(started + 1800)))
    }

    func test_active_ignoresCancelledAndExpiredTimers() {
        XCTAssertNil(FanTimer.active(in: ["timeroff": timer(du: 0, ts: 1_800_000_000)], now: now))
        XCTAssertNil(FanTimer.active(in: ["timeron": timer(du: 5, ts: 1_800_000_000 - 3600)], now: now))
        XCTAssertNil(FanTimer.active(in: [:], now: now))
    }

    func test_active_normalisesAMillisecondStamp() {
        let running = FanTimer.active(in: ["timeron": timer(du: 60, ts: 1_800_000_000_000)], now: now)
        XCTAssertEqual(running?.kind, .turnOn)
        XCTAssertEqual(running?.endsAt, now.addingTimeInterval(3600))
    }

    func test_isSupported_onlyWhenTheFanReportsTheTimer() {
        XCTAssertTrue(FanTimer.isSupported(by: ["timeroff": timer(du: 0, ts: 0)]))
        XCTAssertFalse(FanTimer.isSupported(by: ["timeroff": .int(0)]))
        XCTAssertFalse(FanTimer.isSupported(by: ["poweron": .bool(true)]))
    }

    func test_label_readsAsHoursWherePossible() {
        XCTAssertEqual(FanTimer.presets.map(FanTimer.label(minutes:)), ["None", "30m", "1h", "2h", "4h", "8h"])
    }

    func test_dreoValue_roundTripsAnObject() throws {
        let value = timer(du: 480, ts: 1_793_141_533)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(DreoValue.self, from: data), value)
        XCTAssertEqual(value.description, "{du: 480, ts: 1793141533}")
    }
}
