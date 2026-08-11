import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var lastSelectedDeviceSerialNumber: String?
    /// Set the first time the user reaches the ready state with a device
    /// paired. Used to hide the introductory onboarding screens on
    /// subsequent launches.
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        lastSelectedDeviceSerialNumber: nil,
        hasCompletedOnboarding: false
    )
}
