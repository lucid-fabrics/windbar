import AppKit
import SwiftUI

/// Design tokens for the whole app. Everything reads through here so light
/// and dark stay in step and spacing keeps a single rhythm.
///
/// The palette is sampled from Dreo's own product photography: an open sky
/// over meadow grass and still water. That scene sits almost entirely in a
/// 205 to 213 degree blue, which is why the accent is a sky blue and even
/// the greys are tinted towards it rather than being neutral. Green is
/// taken from the grass and used only to mean healthy.
///
/// Surfaces are translucent tints layered over the menu bar material rather
/// than opaque fills, so the popover keeps its vibrancy in both appearances.
/// Accent colour is reserved for state that is genuinely active; nothing
/// decorative uses it. Every pairing below was checked for contrast: labels
/// on the accent clear 4.5:1, and the accent itself clears 3:1 against its
/// own background.
enum Theme {
    enum Metric {
        static let popoverWidth: CGFloat = 320
        static let cardRadius: CGFloat = 11
        static let controlRadius: CGFloat = 8
        static let cardPadding: CGFloat = 12
        static let gutter: CGFloat = 12
    }

    enum Space {
        static let hairline: CGFloat = 2
        static let tight: CGFloat = 6
        static let snug: CGFloat = 10
        static let roomy: CGFloat = 14
        static let loose: CGFloat = 20
    }

    // MARK: - Palette

    /// Open sky. The one colour allowed to mean "this is on".
    /// Light mode goes deep enough to carry white text (5.1:1); dark mode
    /// takes the bright sky straight from the photograph and pairs it with
    /// a deep navy label instead (7.8:1), which reads better than white on
    /// a light-toned fill.
    static let accent = dynamic(light: 0x1471B8, dark: 0x5FB5F7)

    /// Label colour for anything sitting on `accent`.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0B1B2A)

    /// Meadow green, reserved for a healthy outcome.
    static let success = dynamic(light: 0x5F822B, dark: 0x8CBF40)

    /// Something went wrong. Deliberately the one colour in the app that owes
    /// nothing to the sky palette: an error has to be told apart from "this
    /// is on" at a glance, and the surest way is to sit opposite the accent
    /// rather than beside it. Light clears 5.6:1 on the popover, dark 5.9:1,
    /// so an 11pt caption stays readable in both.
    static let danger = dynamic(light: 0xC0342B, dark: 0xFF6B63)

    /// Filled background behind an error message. Filled, never a border.
    static func dangerSurface(_ scheme: ColorScheme) -> Color {
        danger.opacity(scheme == .dark ? 0.16 : 0.11)
    }

    // MARK: - Accent steps
    //
    // Accent earns its weight by being rare, and the app now has five places
    // that want "accent-ish": a selected chip, a filled slider, the active
    // preset, a card in edit mode, and decorative art. Left to improvise,
    // that became a dozen different opacities, which reads as noise rather
    // than hierarchy. Three named steps instead, loudest to quietest.

    /// A whole surface that has changed mode, e.g. the card while its preset
    /// editor is open. Quiet enough to sit under body text.
    static func accentWash(_ scheme: ColorScheme) -> Color {
        accent.opacity(scheme == .dark ? 0.12 : 0.08)
    }

    /// One row or control that is currently active, e.g. the preset the fan
    /// is running. Loud enough to find at a glance, quiet enough to leave
    /// the label at full contrast instead of forcing it onto a solid fill.
    static func accentTint(_ scheme: ColorScheme) -> Color {
        accent.opacity(scheme == .dark ? 0.18 : 0.14)
    }

    /// Card and control fills. Never a coloured border on a rounded
    /// container: the surface itself carries the hierarchy. Tinted towards
    /// the sky rather than pure white or black, so panels sit in the same
    /// family as the accent instead of looking washed out beside it.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(nsColor: tint(0xBBD9F5)).opacity(0.07)
            : Color(nsColor: tint(0x12456E)).opacity(0.045)
    }

    static func surfaceRaised(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(nsColor: tint(0xBBD9F5)).opacity(0.12)
            : Color(nsColor: tint(0x12456E)).opacity(0.08)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(nsColor: tint(0xBBD9F5)).opacity(0.09)
            : Color(nsColor: tint(0x12456E)).opacity(0.09)
    }

    private static func tint(_ hex: Int) -> NSColor { nsColor(hex) }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Resolves per appearance, so a theme switch repaints without the app
    /// having to observe anything.
    private static func dynamic(light: Int, dark: Int) -> Color {
        let lightColor = nsColor(light)
        let darkColor = nsColor(dark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        })
    }

    enum Font {
        static let deviceName = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let deviceMeta = SwiftUI.Font.system(size: 10, weight: .medium)
        static let sectionLabel = SwiftUI.Font.system(size: 9.5, weight: .semibold)
        static let chip = SwiftUI.Font.system(size: 11, weight: .medium)
        static let row = SwiftUI.Font.system(size: 12.5, weight: .regular)
        static let body = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)
        static let readout = SwiftUI.Font.system(size: 13, weight: .semibold, design: .rounded)
    }
}

/// Uppercase micro-label introducing a control group, with an optional
/// trailing readout such as the current speed.
struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
            Text(title.uppercased())
                .font(Theme.Font.sectionLabel)
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.Space.tight)
            if let trailing {
                Text(trailing)
                    .font(Theme.Font.readout)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
        }
    }
}
