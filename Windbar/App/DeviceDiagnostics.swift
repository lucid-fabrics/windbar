import Foundation

/// Works out which of a fan's own controls this app is not showing.
///
/// Dreo's newer products describe themselves only as `{"template": "<model>"}`
/// and keep the real layout inside the official app, so Windbar renders from
/// a bundled copy of that layout. Where the copy is thin, the fan ends up
/// with a button the app has no control for, which is exactly what a "my fan
/// has oscillation and the app doesn't" report looks like.
///
/// The fan already tells us the truth: its state payload carries every key it
/// publishes. Comparing that against what the schema renders turns a vague
/// report into a list of the exact wire keys that are missing, which is what
/// adding a control needs.
enum DeviceDiagnostics {
    /// Keys carrying connectivity or identity rather than a control, plus
    /// anything that could identify a home or an account. Reports are meant
    /// to be pasted into a public issue, so these never appear.
    ///
    /// Dreo's keys are an inconsistent mix of `snake_case`
    /// (`mcu_firmware_version`) and flat lowercase concatenation
    /// (`devicesn`), with no camelCase boundary to split on, so this is a
    /// curated list rather than a real tokenizer. It used to lean on very
    /// short fragments (`sn`, `ip`, `mac`, `key`, `name`), which cut both
    /// ways: `serialnumber` has no `sn` substring and slipped straight
    /// through, while `ip` matched inside `chipid`/`chipversion` and
    /// redacted exactly the diagnostic this report exists to surface. Every
    /// fragment below is long and specific enough that it should only ever
    /// match a genuinely identifying key; where that trades a false negative
    /// for a false positive, the false positive (redacting something
    /// harmless) is the direction to err in.
    private static let redactedKeyFragments = [
        "devicesn", "serialnumber", "macaddress", "ipaddress", "ssid", "wifi",
        "token", "password", "secret", "devicename",
        "timezone", "latitude", "longitude", "city", "region", "country",
        "accountid", "userid", "deviceid"
    ]

    private static let nonControlKeys: Set<String> = [
        "connected", "poweron", "fanon", "timeron", "timeroff"
    ]

    /// Every cmd the rendered schema can drive.
    static func schemaCommands(_ schema: ControlSchema?) -> Set<String> {
        guard let schema else { return [] }
        var cmds: Set<String> = []
        for section in schema.control + schema.preference {
            if let cmd = section.cmd { cmds.insert(cmd) }
            for item in section.items ?? [] { cmds.insert(item.cmd) }
        }
        return cmds
    }

    /// Keys the fan reports that nothing in the app renders. Sorted so two
    /// reports of the same fan read the same.
    static func unmappedKeys(for device: DreoDevice) -> [String] {
        let known = schemaCommands(device.controlsConf).union(nonControlKeys)
        return device.state.keys
            .filter { !known.contains($0) && !isRedacted($0) }
            .sorted()
    }

    static func isRedacted(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return redactedKeyFragments.contains { lowered.contains($0) }
    }

    /// Report for the clipboard. Carries the model and the unmapped keys with
    /// their current values, since the value is what says whether a key is a
    /// switch, a level or an angle range.
    static func report(for device: DreoDevice, appVersion: String) -> String {
        var lines = [
            "Windbar \(appVersion) device report",
            "Model: \(device.model)"
        ]

        let schema = device.controlsConf
        let rendered = (schema?.control ?? []).map { section in
            let cmds = ((section.items ?? []).map(\.cmd) + [section.cmd].compactMap { $0 })
            return "\(section.type)(\(Set(cmds).sorted().joined(separator: ", ")))"
        }
        lines.append("Controls shown: " + (rendered.isEmpty ? "none" : rendered.joined(separator: ", ")))

        let prefs = (schema?.preference ?? []).compactMap(\.cmd).sorted()
        lines.append("Preferences shown: " + (prefs.isEmpty ? "none" : prefs.joined(separator: ", ")))

        let unmapped = unmappedKeys(for: device)
        if unmapped.isEmpty {
            lines.append("Reported but not shown: none")
        } else {
            lines.append("Reported but not shown:")
            for key in unmapped {
                let value = device.state[key].map(String.init(describing:)) ?? "?"
                lines.append("  \(key) = \(value)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
