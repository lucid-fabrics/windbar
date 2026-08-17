import Foundation

/// How to display the temperature a fan reports.
///
/// Dreo sends `temperature` in Fahrenheit and says so nowhere: there is no
/// unit field on the payload and no unit control in any device template. The
/// evidence is hass-dreo, the Home Assistant integration this project already
/// credits, which publishes the raw value as
/// `native_unit_of_measurement=UnitOfTemperature.FAHRENHEIT` and applies no
/// conversion of its own. So Fahrenheit is the wire unit, and anything else
/// shown is this app converting.
enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    /// Follow the Mac's own region setting. The default, because it is right
    /// for most people without them finding this preference at all.
    case automatic
    case celsius
    case fahrenheit

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }

    /// What `automatic` resolves to on this Mac.
    ///
    /// `Locale.measurementSystem` is the honest source: a US locale means
    /// Fahrenheit, everywhere else means Celsius. Read at call time rather
    /// than cached, so changing the region in System Settings is reflected
    /// without relaunching.
    private var resolved: UnitTemperature {
        switch self {
        case .celsius: .celsius
        case .fahrenheit: .fahrenheit
        case .automatic: Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        }
    }

    /// Formats a Fahrenheit reading from the fan for display.
    ///
    /// Rounded to whole degrees on purpose. The sensor sits inside a moving
    /// fan and is documented as inaccurate by every integration that exposes
    /// it, so a decimal place would be false precision.
    func format(fahrenheit: Int) -> String {
        let measurement = Measurement(value: Double(fahrenheit), unit: UnitTemperature.fahrenheit)
        let degrees = measurement.converted(to: resolved).value.rounded()
        // Formatted by hand rather than with MeasurementFormatter: that
        // inserts a space before the symbol ("23 °C"), and this string sits in
        // a cramped menu bar line next to a middot separator.
        return "\(Int(degrees))°\(resolved == .fahrenheit ? "F" : "C")"
    }
}
