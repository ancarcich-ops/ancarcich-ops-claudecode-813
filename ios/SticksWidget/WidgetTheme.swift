//
//  WidgetTheme.swift
//  SticksWidget
//
//  Design tokens duplicated for the widget extension target (extension
//  targets can't see files in the Sticks/ folder). Two palettes live
//  here: the legacy Sticks tokens (home screen widget) and the "Caddie"
//  skin the Live Activity lock screen card + Dynamic Island use.
//

import SwiftUI
import UIKit

extension Color {
    /// Cream panel/card surface — #F7F3EA (web `panel`)
    static let sticksCream = Color(red: 247 / 255, green: 243 / 255, blue: 234 / 255)

    /// Deep green accent — #285E45 (web `accent`)
    static let sticksGreen = Color(red: 40 / 255, green: 94 / 255, blue: 69 / 255)

    /// Sticks green lifted for legibility on the Dynamic Island's black.
    static let sticksGreenBright = Color(red: 0.45, green: 0.76, blue: 0.56)

    /// Primary text on cream — #26221C (web `ink`)
    static let sticksInk = Color(red: 38 / 255, green: 34 / 255, blue: 28 / 255)

    /// Muted text on cream — #746C5C (web `mute`)
    static let sticksMuted = Color(red: 116 / 255, green: 108 / 255, blue: 92 / 255)

    /// Eagle / FINISH ROUND gold — #A9762A (web `gold`)
    static let sticksGold = Color(red: 169 / 255, green: 118 / 255, blue: 42 / 255)

    // MARK: - Caddie skin (Live Activity card)

    /// Card shell fill — #F5EFE0 (rendered at 97%).
    static let caddieShell = Color(red: 245 / 255, green: 239 / 255, blue: 224 / 255)

    /// Card border — #D8CDB4 (rendered at 90%).
    static let caddieBorder = Color(red: 216 / 255, green: 205 / 255, blue: 180 / 255)

    /// Ink — #211D16. Primary text; also the in-play strip segment.
    static let caddieInk = Color(red: 33 / 255, green: 29 / 255, blue: 22 / 255)

    /// Labels, units, hairline base, par strip segments — #8A7C62.
    static let caddieLabel = Color(red: 138 / 255, green: 124 / 255, blue: 98 / 255)

    /// Secondary emphasis inside labels — #6E6552.
    static let caddieSub = Color(red: 110 / 255, green: 101 / 255, blue: 82 / 255)

    /// Under par — conventional golf green #217A4B (deliberate override
    /// of the app's usual palette mapping, per the Caddie card spec).
    static let caddieGreen = Color(red: 33 / 255, green: 122 / 255, blue: 75 / 255)

    /// Over par + the flag glyph — #B4382B.
    static let caddieRed = Color(red: 180 / 255, green: 56 / 255, blue: 43 / 255)

    // MARK: - Dynamic Island (dark tokens on the black pill)

    /// Island flag + under-par green — #34D399.
    static let islandFlag = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)

    /// Island numerals — #F2EEDF.
    static let islandDigits = Color(red: 242 / 255, green: 238 / 255, blue: 223 / 255)

    /// Island units/labels — #8A938C.
    static let islandUnit = Color(red: 138 / 255, green: 147 / 255, blue: 140 / 255)

    /// Over-par red lifted for legibility on black — pairs with #34D399.
    static let islandRed = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
}

/// Widget-side font helpers. The TTFs are bundled IN THE EXTENSION
/// target and registered in the widget's own Info.plist (fonts in the
/// app's Info.plist are invisible here). Falls back to the closest
/// system font if a bundled font fails to load — never blank text.
enum WidgetFont {
    // Availability checked once per family and cached.
    private static let hasNewsreader = UIFont(name: "Newsreader-Bold", size: 12) != nil
    private static let hasDMMono = UIFont(name: "DMMono-Medium", size: 12) != nil

    /// Display serif (Newsreader 700) — hole titles.
    static func display(_ size: CGFloat) -> Font {
        guard hasNewsreader else {
            return .system(size: size, weight: .bold, design: .serif)
        }
        return .custom("Newsreader-Bold", size: size)
    }

    /// Mono (DM Mono 400/500) — yardages, labels, meta rows. Medium is
    /// the family's heaviest weight, so it stands in for "bold".
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        guard hasDMMono else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return .custom("DMMono-Regular", size: size)
        default:
            return .custom("DMMono-Medium", size: size)
        }
    }
}
