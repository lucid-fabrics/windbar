import Foundation
import os

/// English text for the localisation keys the Dreo API sends instead of
/// readable labels.
///
/// Older devices return raw keys in their `controlsConf`, so a control comes
/// across as `device_control_panelsound` rather than "Panel Sound". Splitting
/// those on underscores gets close but not there: that key has no separator
/// between the two words, so it renders as "Panelsound", and
/// `device_fans_mode_straight` reads as "Straight" when the official app calls
/// it "Normal".
///
/// `Labels.json` is the vendor app's own English string table, cut down to the
/// keys that appear in device schemas, so labels match what the Dreo app shows.
enum DeviceLabels {
    private static let logger = Logger(subsystem: "com.lucidfabrics.windbar", category: "DeviceLabels")

    private static let table: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Labels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            logger.warning("Labels.json missing or unreadable")
            return [:]
        }
        return decoded
    }()

    /// The English label for a key, or nil when this app has no entry, in
    /// which case the caller falls back to tidying the key itself.
    static func text(forKey key: String) -> String? {
        table[key]
    }

    static var count: Int { table.count }
}

extension String {
    /// Schemas from the server carry raw localisation keys such as
    /// `device_control_mode_sleep`, while the bundled templates already hold
    /// English. Keys are looked up in the vendor's own string table first, so
    /// labels read the way the Dreo app words them, and anything unknown falls
    /// back to tidying the key itself.
    var dreoTitleCased: String {
        if let label = DeviceLabels.text(forKey: self) { return label }
        guard contains("_") else { return self }
        var words = split(separator: "_").map(String.init)
            .filter { !["device", "control", "fans", "base"].contains($0.lowercased()) }
        if words.count > 1, words.first?.lowercased() == "mode" {
            words.removeFirst()
        }
        if words.isEmpty { words = [self] }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
