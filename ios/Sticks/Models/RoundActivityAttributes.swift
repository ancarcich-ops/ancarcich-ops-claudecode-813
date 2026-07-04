//
//  RoundActivityAttributes.swift
//  Sticks
//
//  ⚠️ Shared between the Sticks app and the SticksWidget extension —
//  ActivityKit matches Live Activities by type name and Codable shape,
//  so this copy and SticksWidget/RoundActivityAttributes.swift MUST
//  stay identical.
//

import ActivityKit
import Foundation

nonisolated struct RoundActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// Absolute hole number currently being played/viewed.
        var hole: Int
        var par: Int
        /// Rounded yardages to the green — nil when no GPS data exists.
        var frontYds: Int?
        var centerYds: Int?
        var backYds: Int?
        /// Holes the caller has scored so far.
        var holesScored: Int
        var totalHoles: Int
        /// Caller's running score relative to par — nil for spectators
        /// or before any hole is scored.
        var myToPar: Int?
    }

    var courseName: String
    var matchId: String
}
