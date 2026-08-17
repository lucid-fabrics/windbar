import SwiftUI
import XCTest
@testable import Windbar

final class ColorSwatchesTests: XCTestCase {
    func test_packedRGB_unpacksEachChannel() {
        // The fan stores colour as one 24-bit integer, so a wrong shift shows
        // up as the right colour on the wrong channel.
        XCTAssertEqual(ColorSwatches.color(fromPackedRGB: 0xFF0000), Color(red: 1, green: 0, blue: 0))
        XCTAssertEqual(ColorSwatches.color(fromPackedRGB: 0x00FF00), Color(red: 0, green: 1, blue: 0))
        XCTAssertEqual(ColorSwatches.color(fromPackedRGB: 0x0000FF), Color(red: 0, green: 0, blue: 1))
        XCTAssertEqual(ColorSwatches.color(fromPackedRGB: 0xFFFFFF), Color(red: 1, green: 1, blue: 1))
    }

    func test_tickInkFlipsWithSwatchLightness() {
        // The tick sits on the swatch itself, so it has to invert or it
        // disappears on white and on black alike.
        XCTAssertEqual(ColorSwatches.contrastingInk(forPackedRGB: 0xFFFFFF), .black)
        XCTAssertEqual(ColorSwatches.contrastingInk(forPackedRGB: 0xFFFF00), .black)
        XCTAssertEqual(ColorSwatches.contrastingInk(forPackedRGB: 0x000000), .white)
        XCTAssertEqual(ColorSwatches.contrastingInk(forPackedRGB: 0x0000FF), .white)
    }

    /// Every swatch has to be a value the fan will actually take: it accepts
    /// 0 through 0xFFFFFF and refuses anything above.
    func test_bundledPaletteStaysInsideTheRangeTheFanAccepts() throws {
        let schema = try XCTUnwrap(DeviceTemplateCatalog.schema(forModel: "DR-HPF008S"))
        let colors = try XCTUnwrap(schema.control.first { $0.type == "Color" })
        let values = (colors.items ?? []).compactMap(\.value.intValue)

        XCTAssertEqual(values.count, colors.items?.count)
        XCTAssertGreaterThanOrEqual(values.min() ?? -1, 0)
        XCTAssertLessThanOrEqual(values.max() ?? .max, 0xFFFFFF)
        XCTAssertEqual(Set((colors.items ?? []).map(\.cmd)), ["atmcolor"])
    }
}
