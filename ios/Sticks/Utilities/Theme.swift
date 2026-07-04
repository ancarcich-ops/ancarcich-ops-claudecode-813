//
//  Theme.swift
//  Sticks
//
//  Design tokens matching the Sticks web app's light theme, exact hex
//  values from the web CSS variables — cream background, deep green
//  accent, serif display numerals, monospaced scorecard digits.
//

import SwiftUI

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

enum SticksFont {
    /// Big serif display numerals / wordmark
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small uppercase label type
    static func label(_ size: CGFloat = 12, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Monospaced score numerals (web: DM Mono) so scorecard columns align.
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum SticksMetrics {
    /// Card corner radius shared with the web app.
    static let cardRadius: CGFloat = 14
}
