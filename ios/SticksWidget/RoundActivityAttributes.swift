//
//  RoundActivityAttributes.swift
//  SticksWidget
//
//  ⚠️ Shared between the Sticks app and the SticksWidget extension —
//  ActivityKit matches Live Activities by type name and Codable shape,
//  so this copy and Sticks/Models/RoundActivityAttributes.swift MUST
//  stay byte-identical (same type names, same properties, same order).
//

import ActivityKit
import Foundation

nonisolated struct RoundActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// Absolute hole number currently being played/viewed.
        var hole: Int
        var par: Int
        /// Yards to the pin — nil when no GPS fix or no green mapped.
        var toPinYds: Int?
        var frontYds: Int?
        var backYds: Int?
        /// Holes where every player has a score.
        var holesScored: Int
        /// 9 or 18.
        var totalHoles: Int
        /// Caller's running score vs par — nil for spectators.
        var myToPar: Int?
        /// Wearer's (strokes − par) per hole — exactly totalHoles entries,
        /// index = round order, nil = not yet scored (all nil for spectators).
        var holeDiffs: [Int?]
        /// Round-order index of the hole in play — drives the progress
        /// strip's in-play marker correctly for non-hole-1 starts.
        var holeRoundIndex: Int
        /// Stamped by RoundActivityService at push time.
        var updatedAt: Date
    }

    var matchId: String
    var courseName: String
}
