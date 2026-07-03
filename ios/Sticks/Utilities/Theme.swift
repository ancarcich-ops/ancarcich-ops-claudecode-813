//
//  Theme.swift
//  Sticks
//
//  Design tokens matching the Sticks web app: cream background,
//  deep green accent, serif display numerals.
//

import SwiftUI

extension Color {
    /// Cream app background — #F7F3EA
    static let sticksCream = Color(red: 247 / 255, green: 243 / 255, blue: 234 / 255)

    /// Deep green accent — #285E45
    static let sticksGreen = Color(red: 40 / 255, green: 94 / 255, blue: 69 / 255)

    /// Slightly darker green for pressed states — #1E4A36
    static let sticksGreenDark = Color(red: 30 / 255, green: 74 / 255, blue: 54 / 255)

    /// Ink color for primary text on cream — #23281F
    static let sticksInk = Color(red: 35 / 255, green: 40 / 255, blue: 31 / 255)

    /// Muted text on cream — #7A7668
    static let sticksMuted = Color(red: 122 / 255, green: 118 / 255, blue: 104 / 255)

    /// Card surface, a touch lighter than the cream — #FDFBF5
    static let sticksCard = Color(red: 253 / 255, green: 251 / 255, blue: 245 / 255)

    /// Hairline borders on cream — #E3DCCB
    static let sticksHairline = Color(red: 227 / 255, green: 220 / 255, blue: 203 / 255)

    /// Error red tuned for the cream palette — #A63D2F
    static let sticksError = Color(red: 166 / 255, green: 61 / 255, blue: 47 / 255)
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
}
