import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var lastSelectedDeviceSerialNumber: String?
    /// Set the first time the user reaches the ready state with a device
    /// paired. Used to hide the introductory onboarding screens on
    /// subsequent launches.
    var hasCompletedOnboarding: Bool
    /// Presets keyed by device serial number. Each device carries its own
    /// list of named shortcuts; the dict is empty (and reads back as `[]`
    /// after a fresh install) until the user saves one.
    var presetsBySerialNumber: [String: [DevicePreset]]

    static let `default` = AppSettings(
        lastSelectedDeviceSerialNumber: nil,
        hasCompletedOnboarding: false,
        presetsBySerialNumber: [:]
    )

    init(
        lastSelectedDeviceSerialNumber: String?,
        hasCompletedOnboarding: Bool,
        presetsBySerialNumber: [String: [DevicePreset]]
    ) {
        self.lastSelectedDeviceSerialNumber = lastSelectedDeviceSerialNumber
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.presetsBySerialNumber = presetsBySerialNumber
    }

    /// Decodes a key at a time so an older settings blob still loads.
    ///
    /// The synthesized decoder throws `keyNotFound` for a field the stored
    /// JSON predates, and `SettingsRepository.load()` answers a throw with
    /// `.default`. Adding `presetsBySerialNumber` as a required key therefore
    /// silently reset every existing user: their `hasCompletedOnboarding`
    /// went back to false, so a token expiry dropped them into the first-run
    /// wizard instead of the login screen, and their last-used fan was
    /// forgotten. Every field here has to stay optional on read.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSelectedDeviceSerialNumber = try container.decodeIfPresent(
            String.self, forKey: .lastSelectedDeviceSerialNumber)
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self, forKey: .hasCompletedOnboarding) ?? false
        presetsBySerialNumber = try container.decodeIfPresent(
            [String: [DevicePreset]].self, forKey: .presetsBySerialNumber) ?? [:]
    }
}
