//
//  RoundSnapshot.swift
//  Sticks
//
//  ⚠️ Shared between the Sticks iOS app and the SticksWatch app — it
//  crosses WatchConnectivity as JSON (field names are the wire format),
//  so this copy and SticksWatch/RoundSnapshot.swift MUST stay identical.
//

import Foundation

nonisolated struct RoundSnapshot: Codable, Hashable {
    var courseName: String
    var hole: Int
    /// Round index (0-based) of the current hole — the index space for
    /// the watch's setHole command.
    var holeIndex: Int
    var par: Int
    var frontYds: Int?
    var centerYds: Int?
    var backYds: Int?
    var holesScored: Int
    var totalHoles: Int
    var myToPar: Int?
    /// Wearer has a seat in the match — gates watch score entry.
    var isSeated: Bool
    /// Wearer's score on the CURRENT hole, if any.
    var myScore: Int?
    var updatedAt: Date
}
