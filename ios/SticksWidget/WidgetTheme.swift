//
//  WidgetTheme.swift
//  SticksWidget
//
//  Sticks design tokens duplicated for the widget extension target
//  (extension targets can't see files in the Sticks/ folder).
//

import SwiftUI

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
}
