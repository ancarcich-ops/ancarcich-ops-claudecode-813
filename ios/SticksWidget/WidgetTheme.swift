//
//  WidgetTheme.swift
//  SticksWidget
//
//  Sticks design tokens duplicated for the widget extension target
//  (extension targets can't see files in the Sticks/ folder).
//

import SwiftUI

extension Color {
    /// Cream app background — #F7F3EA
    static let sticksCream = Color(red: 247 / 255, green: 243 / 255, blue: 234 / 255)

    /// Deep green accent — #285E45
    static let sticksGreen = Color(red: 40 / 255, green: 94 / 255, blue: 69 / 255)

    /// Sticks green lifted for legibility on the Dynamic Island's black.
    static let sticksGreenBright = Color(red: 0.45, green: 0.76, blue: 0.56)

    /// Ink color for primary text on cream — #23281F
    static let sticksInk = Color(red: 35 / 255, green: 40 / 255, blue: 31 / 255)

    /// Muted text on cream — #7A7668
    static let sticksMuted = Color(red: 122 / 255, green: 118 / 255, blue: 104 / 255)

    /// Trophy gold — #C9A227
    static let sticksGold = Color(red: 201 / 255, green: 162 / 255, blue: 39 / 255)
}
