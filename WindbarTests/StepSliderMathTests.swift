import XCTest
@testable import Windbar

/// Pins the two behaviours issue feedback called out: speed 1 must not look
/// like "off" (the fill), and the icon must read as a running fan (the spin).
/// Both live in pure functions precisely so this file can hold them still.
final class StepSliderMathTests: XCTestCase {
    private let nineSpeeds = 1...9

    /// The complaint verbatim: "Speed 1 being the first dot (no blue bar)
    /// makes me feel like it's off." The lowest speed now fills exactly one
    /// of the (steps + 1) segments, never zero.
    func test_lowestSpeed_fillsOneWholeSegment() {
        let fill = StepSlider.fillFraction(value: 1, range: nineSpeeds)
        XCTAssertEqual(fill, 1.0 / 9.0, accuracy: 0.0001)
        XCTAssertGreaterThan(fill, 0, "an empty bar at speed 1 reads as off")
    }

    func test_topSpeed_fillsTheWholeTrack() {
        XCTAssertEqual(StepSlider.fillFraction(value: 9, range: nineSpeeds), 1.0, accuracy: 0.0001)
    }

    func test_fill_growsStrictlyWithEverySpeed() {
        let fills = nineSpeeds.map { StepSlider.fillFraction(value: $0, range: nineSpeeds) }
        for (below, above) in zip(fills, fills.dropFirst()) {
            XCTAssertLessThan(below, above)
        }
    }

    /// Ticks at or below the current speed are drawn on the accent fill, so
    /// the fill edge must sit at or past every such tick's position. Breaking
    /// this puts an "on accent" coloured tick on the bare track.
    func test_fillEdge_coversEveryTickAtOrBelowTheCurrentSpeed() {
        for value in nineSpeeds {
            let fillEdge = StepSlider.fillFraction(value: value, range: nineSpeeds)
            for step in nineSpeeds.lowerBound...value {
                let tickPosition = Double(step - nineSpeeds.lowerBound)
                    / Double(nineSpeeds.upperBound - nineSpeeds.lowerBound)
                XCTAssertGreaterThanOrEqual(fillEdge, tickPosition,
                    "tick for speed \(step) sticks out of the fill at speed \(value)")
            }
        }
    }

    /// Clicking exactly on a dot must select that dot's speed, unchanged by
    /// the new fill geometry: the drag still maps by nearest tick.
    func test_clickingEachDot_selectsThatSpeed() {
        for value in nineSpeeds {
            let dotRatio = Double(value - nineSpeeds.lowerBound)
                / Double(nineSpeeds.upperBound - nineSpeeds.lowerBound)
            XCTAssertEqual(StepSlider.step(atRatio: dotRatio, range: nineSpeeds), value)
        }
    }

    func test_dragOutsideTheTrack_clampsToTheEnds() {
        XCTAssertEqual(StepSlider.step(atRatio: -0.5, range: nineSpeeds), 1)
        XCTAssertEqual(StepSlider.step(atRatio: 1.5, range: nineSpeeds), 9)
    }

    /// A two-value range (some Dreo products) must still span empty-ish to full.
    func test_twoSpeedRange_fillsHalfThenFull() {
        XCTAssertEqual(StepSlider.fillFraction(value: 0, range: 0...1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StepSlider.fillFraction(value: 1, range: 0...1), 1.0, accuracy: 0.0001)
    }

    // MARK: - Fan icon spin

    /// One revolution every two seconds, always within [0, 360).
    func test_spinAngle_completesOneRevolutionEveryTwoSeconds() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let angle = DeviceHeaderView.spinAngle(at: start)
        XCTAssertEqual(DeviceHeaderView.spinAngle(at: start.addingTimeInterval(2)), angle, accuracy: 0.0001)
        XCTAssertEqual(DeviceHeaderView.spinAngle(at: start.addingTimeInterval(0.5)),
                       (angle + 90).truncatingRemainder(dividingBy: 360), accuracy: 0.0001)
    }

    func test_spinAngle_staysWithinACircle() {
        for offset in stride(from: 0.0, through: 10.0, by: 0.25) {
            let angle = DeviceHeaderView.spinAngle(at: Date(timeIntervalSinceReferenceDate: offset))
            XCTAssertGreaterThanOrEqual(angle, 0)
            XCTAssertLessThan(angle, 360)
        }
    }
}
