//
//  WatchScoreStyle.swift
//  SticksWatch
//
//  Par-relative color + label mapping, matching the phone's ScoreStyle
//  language (gold = eagle+, green = under, red = over) tuned for the
//  watch's black background.
//

import SwiftUI

struct WatchScoreStyle {
    let background: Color
    let text: Color

    /// Style for `score` on a hole of the given par.
    static func forScore(_ score: Int, par: Int) -> WatchScoreStyle {
        switch score - par {
        case ..<(-1):
            WatchScoreStyle(background: .sticksGold, text: .sticksCream)
        case -1:
            WatchScoreStyle(background: .sticksGreen, text: .sticksCream)
        case 0:
            WatchScoreStyle(background: Color.sticksGreen.opacity(0.5), text: .white)
        case 1:
            WatchScoreStyle(background: Color.sticksDanger.opacity(0.6), text: .white)
        default:
            WatchScoreStyle(background: .sticksDanger, text: .white)
        }
    }

    /// Big par-relative label for the score stepper ("BOGEY", "BIRDIE"…).
    static func relativeLabel(for score: Int, par: Int) -> String {
        if score == 1 { return "ACE" }
        switch score - par {
        case ..<(-2): return "ALBATROSS"
        case -2: return "EAGLE"
        case -1: return "BIRDIE"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DOUBLE"
        case 3: return "TRIPLE"
        case let diff: return "+\(diff)"
        }
    }
}
