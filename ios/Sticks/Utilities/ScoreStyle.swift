//
//  ScoreStyle.swift
//  Sticks
//
//  Score-state colors matching the Sticks web app: the fill encodes the
//  par-relation, the stroke number inside disambiguates. Shared by the
//  match detail scorecard grid, the GPS hole rail, and the score entry
//  sheet's par-relative chips.
//

import SwiftUI

struct ScoreStyle {
    let fill: Color
    let text: Color
    let border: Color
    /// Thin glow ring for the extremes (eagle or better, double bogey+).
    let ring: Color?

    /// Style for `score` on a hole of the given par. nil = unplayed.
    static func forScore(_ score: Int?, par: Int) -> ScoreStyle {
        guard let score else {
            // Unplayed: border-only outline, no fill.
            return ScoreStyle(fill: .clear, text: .sticksMuted, border: .sticksHairline, ring: nil)
        }
        switch score - par {
        case ..<(-1):
            // Eagle or better: solid gold, cream text, thin gold glow ring.
            return ScoreStyle(fill: .sticksGold, text: .sticksCream, border: .clear, ring: .sticksGold)
        case -1:
            // Birdie: solid accent green, cream text.
            return ScoreStyle(fill: .sticksGreen, text: .sticksCream, border: .clear, ring: nil)
        case 0:
            // Par: accent at 15% fill, accent at 30% border.
            return ScoreStyle(
                fill: Color.sticksGreen.opacity(0.15),
                text: .sticksInk,
                border: Color.sticksGreen.opacity(0.3),
                ring: nil
            )
        case 1:
            // Bogey: danger at 55%, white text.
            return ScoreStyle(fill: Color.sticksError.opacity(0.55), text: .white, border: .clear, ring: nil)
        default:
            // Double bogey or worse: solid danger, white text, thin ring.
            return ScoreStyle(fill: .sticksError, text: .white, border: .clear, ring: .sticksError)
        }
    }
}
