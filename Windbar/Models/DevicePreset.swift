import Foundation

/// A named shape for one device: speed, mode, oscillation, everything except
/// whether the fan is running.
///
/// The dict carries the same cmd keys the device itself publishes
/// (e.g. `windlevel`, `hoscangle`), so applying a preset is just "send every
/// value in the dict". Storing the full shape instead of a delta means a
/// preset still does the right thing if the device has drifted into an
/// unknown state.
///
/// Power is deliberately not part of a shape. Running a preset implies
/// turning the fan on, and turning it off belongs to the power switch, so a
/// preset never has to answer "on or off" twice.
struct DevicePreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var values: [String: DreoValue]

    init(id: UUID = UUID(), name: String, values: [String: DreoValue]) {
        self.id = id
        self.name = name
        self.values = values
    }

    /// The values minus power. Presets saved before power was excluded still
    /// carry `poweron`/`fanon`, so it is stripped on read rather than through
    /// a settings migration.
    func shape(powerKey: String) -> [String: DreoValue] {
        values.filter { $0.key != powerKey && $0.key != "poweron" && $0.key != "fanon" }
    }
}
