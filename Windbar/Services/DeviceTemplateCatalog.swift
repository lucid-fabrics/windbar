import Foundation
import os

/// Control schemas for Dreo models the server declines to describe.
///
/// Older products ship a full `controlsConf` in the device-list response,
/// which the app renders generically. Newer ones send only
/// `{"template": "<model>"}` and keep the real layout inside the official
/// app. `DeviceTemplates.json` is that layout, lifted from the vendor app's
/// bundled `app_config.json` with its labels already resolved to English,
/// and reshaped into the same `ControlSchema` the server sends, so both
/// paths render through identical code.
enum DeviceTemplateCatalog {
    private static let logger = Logger(subsystem: "com.lucidfabrics.windbar", category: "DeviceTemplateCatalog")

    private static let catalog: [String: ControlSchema] = {
        let generated = load("DeviceTemplates")
        let overrides = load("DeviceTemplateOverrides")
        guard !overrides.isEmpty else { return generated }

        var merged = generated
        for (model, override) in overrides {
            merged[model] = apply(override, to: merged[model] ?? ControlSchema())
        }
        return merged
    }()

    private static func load(_ resource: String) -> [String: ControlSchema] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            logger.warning("\(resource, privacy: .public).json missing from bundle")
            return [:]
        }
        do {
            // The overrides file carries `_readme` and `_source` notes, which
            // are not models. Decoding is already lossy per entry, so they
            // drop out on their own the way an unfamiliar device does.
            return try JSONDecoder().decode([String: ControlSchema].self, from: data)
                .filter { !$0.key.hasPrefix("_") }
        } catch {
            let reason = "\(resource): \(String(describing: error))"
            logger.warning("Bundled template file unreadable, \(reason, privacy: .public)")
            return [:]
        }
    }

    /// Layers hand-maintained corrections over a generated template.
    ///
    /// Additive only. A section whose id matches one in the generated
    /// template contributes its items to that section, which is how a mode
    /// the vendor config omits gets added without restating the other four.
    /// Anything else is appended as a new control. Nothing is ever removed,
    /// so an override cannot quietly delete a control the fan really has.
    static func apply(_ override: ControlSchema, to base: ControlSchema) -> ControlSchema {
        var control = base.control
        for section in override.control {
            guard let index = control.firstIndex(where: { $0.id == section.id }) else {
                control.append(section)
                continue
            }
            let existing = control[index]
            control[index] = ControlSection(
                rawId: existing.rawId,
                type: existing.type,
                title: existing.title,
                cmd: existing.cmd,
                items: dedupedItems((existing.items ?? []) + (section.items ?? [])),
                reverse: existing.reverse,
                trueValue: existing.trueValue,
                falseValue: existing.falseValue,
                // An override may add a prerequisite the vendor never
                // described, so it wins where the base has none.
                requires: section.requires ?? existing.requires
            )
        }

        var preference = base.preference
        for section in override.preference where !preference.contains(where: { $0.id == section.id }) {
            preference.append(section)
        }
        return ControlSchema(control: control, preference: preference)
    }

    /// Collapses an item list to one entry per `ControlItem.id`
    /// (`cmd_value`), keeping the last occurrence and the position of the
    /// first.
    ///
    /// An override's items are always concatenated onto the generated
    /// template's, never replacing them, so an override restating a value
    /// the base already has (correcting a label, say) used to leave two
    /// `ControlItem`s sharing the same id in the same `ForEach`, which is
    /// undefined behaviour in SwiftUI. Nothing currently in the bundle
    /// triggers this, but the override file is hand-maintained and the
    /// generated one is regenerated independently, which is exactly how the
    /// two would drift into overlapping some day. Keeping the last write
    /// means the override's correction is the one that survives.
    static func dedupedItems(_ items: [ControlItem]) -> [ControlItem] {
        var order: [String] = []
        var byID: [String: ControlItem] = [:]
        for item in items {
            if byID[item.id] == nil { order.append(item.id) }
            byID[item.id] = item
        }
        return order.compactMap { byID[$0] }
    }

    /// Bundled schema for a model, or nil when this app has no template for it.
    static func schema(forModel model: String) -> ControlSchema? {
        catalog[model]
    }

    static var modelCount: Int { catalog.count }
}
