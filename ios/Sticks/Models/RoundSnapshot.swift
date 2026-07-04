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
    var par: Int
    var frontYds: Int?
    var centerYds: Int?
    var backYds: Int?
    var holesScored: Int
    var totalHoles: Int
    var myToPar: Int?
    var updatedAt: Date
}
