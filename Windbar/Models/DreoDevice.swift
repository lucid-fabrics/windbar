import Foundation

/// A single Dreo device plus its live state, as reported by the device-state
/// REST call and kept current by websocket push updates.
struct DreoDevice: Identifiable, Equatable, Sendable {
    let serialNumber: String
    let deviceName: String
    let model: String
    let controlsConf: ControlSchema?
    var state: [String: DreoValue]

    var id: String { serialNumber }

    init(
        serialNumber: String,
        deviceName: String,
        model: String,
        controlsConf: ControlSchema?,
        state: [String: DreoValue] = [:]
    ) {
        self.serialNumber = serialNumber
        self.deviceName = deviceName
        self.model = model
        self.controlsConf = controlsConf
        self.state = state
    }

    /// Whether the device is currently reachable through Dreo's cloud. A
    /// device that never reports `connected` is assumed reachable, so an
    /// older product is not shown as offline purely for staying quiet.
    var isOnline: Bool {
        state["connected"]?.boolValue ?? true
    }

    /// Some Dreo devices report power as `poweron`, others as `fanon`.
    var powerKey: String {
        state["poweron"] != nil ? "poweron" : "fanon"
    }

    var isOn: Bool {
        state[powerKey]?.boolValue ?? false
    }

    /// Misting fans report their pump as `miston`; nothing else does.
    var isMisting: Bool {
        isOn && state["miston"]?.boolValue == true
    }

    /// Relative humidity in percent, for the models with a sensor.
    var humidity: Int? {
        state["rh"]?.intValue
    }

    /// `wrong` is 1 when a misting fan's tank runs dry, per hass-dreo's
    /// evaporative cooler driver. Scoped to misting models, since other
    /// products may use the same key for something else.
    /// ponytail: read from hass-dreo, not seen on hardware; confirm on the 765S (issue #3).
    var isWaterTankEmpty: Bool {
        state["miston"] != nil && state["wrong"]?.intValue == 1
    }

    mutating func apply(_ updates: [String: DreoValue]) {
        for (key, value) in updates {
            state[key] = value
        }
    }
}
