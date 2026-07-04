//
//  Theme.swift
//  Sticks
//
//  Design tokens matching the Sticks web app's light theme, exact hex
//  values from the web CSS variables — cream background, deep green
//  accent, serif display numerals, monospaced scorecard digits.
//

import SwiftUI
import UIKit

extension Color {
    /// Page background — #EDE7DB (web `bg`)
    static let sticksBg = Color(red: 237 / 255, green: 231 / 255, blue: 219 / 255)

    /// Panel/card surface — #F7F3EA (web `panel`). Also the "cream" text
    /// color on green/gold fills.
    static let sticksCream = Color(red: 247 / 255, green: 243 / 255, blue: 234 / 255)

    /// Card surface — same #F7F3EA panel value, named for call sites.
    static let sticksCard = Color(red: 247 / 255, green: 243 / 255, blue: 234 / 255)

    /// Nested/secondary surfaces — #F0EADF (web `panel2`)
    static let sticksPanel2 = Color(red: 240 / 255, green: 234 / 255, blue: 223 / 255)

    /// Borders and hairlines — #D6CEBE (web `border`)
    static let sticksHairline = Color(red: 214 / 255, green: 206 / 255, blue: 190 / 255)

    /// Primary text (not pure black) — #26221C (web `ink`)
    static let sticksInk = Color(red: 38 / 255, green: 34 / 255, blue: 28 / 255)

    /// Secondary text — #746C5C (web `mute`)
    static let sticksMuted = Color(red: 116 / 255, green: 108 / 255, blue: 92 / 255)

    /// Deep green accent — #285E45 (web `accent`)
    static let sticksGreen = Color(red: 40 / 255, green: 94 / 255, blue: 69 / 255)

    /// Pressed/darker green — #1C4E38 (web `accentDim`)
    static let sticksGreenDark = Color(red: 28 / 255, green: 78 / 255, blue: 56 / 255)

    /// Over-par red — #9A2B26 (web `danger`)
    static let sticksError = Color(red: 154 / 255, green: 43 / 255, blue: 38 / 255)

    /// Eagle / FINISH ROUND gold — #A9762A (web `gold`)
    static let sticksGold = Color(red: 169 / 255, green: 118 / 255, blue: 42 / 255)
}

/// The web app's three embedded families — Newsreader (display),
/// Karla (sans) and DM Mono (mono) — registered via UIAppFonts.
/// Every helper falls back to the closest system font if a bundled
/// font fails to load: never crash, never render blank text.
enum SticksFont {
    // Availability is checked once per family and cached.
    private static let hasNewsreader = UIFont(name: "Newsreader-SemiBold", size: 12) != nil
    private static let hasNewsreaderItalic = UIFont(name: "Newsreader-SemiBoldItalic", size: 12) != nil
    private static let hasKarla = UIFont(name: "Karla-Regular", size: 12) != nil
    private static let hasDMMono = UIFont(name: "DMMono-Medium", size: 12) != nil

    /// Display serif (Newsreader): headings, big numerals, wordmark,
    /// score digits. Weights 500/600/700.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        guard hasNewsreader else {
            return .system(size: size, weight: weight, design: .serif)
        }
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Newsreader-Bold"
        case .ultraLight, .thin, .light, .regular, .medium:
            name = "Newsreader-Medium"
        default:
            name = "Newsreader-SemiBold"
        }
        return .custom(name, size: size)
    }

    /// Italic display serif (Newsreader italic 600) — editorial accents.
    static func displayItalic(_ size: CGFloat) -> Font {
        guard hasNewsreaderItalic else {
            return .system(size: size, weight: .semibold, design: .serif).italic()
        }
        return .custom("Newsreader-SemiBoldItalic", size: size)
    }

    /// Body sans (Karla): body text, player names, buttons.
    /// Weights 400/600/700.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard hasKarla else {
            return .system(size: size, weight: weight)
        }
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Karla-Bold"
        case .medium, .semibold:
            name = "Karla-SemiBold"
        default:
            name = "Karla-Regular"
        }
        return .custom(name, size: size)
    }

    /// Mono (DM Mono): labels, hole numbers, all-caps meta rows, and
    /// in-cell score numbers so columns align. Weights 400/500.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        guard hasDMMono else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        let name: String
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            name = "DMMono-Regular"
        default:
            name = "DMMono-Medium"
        }
        return .custom(name, size: size)
    }

    /// Small uppercase label type — DM Mono, matching the web's meta rows.
    static func label(_ size: CGFloat = 12, weight: Font.Weight = .semibold) -> Font {
        mono(size, weight: weight)
    }
}

enum SticksMetrics {
    /// Card corner radius shared with the web app.
    static let cardRadius: CGFloat = 14
}
