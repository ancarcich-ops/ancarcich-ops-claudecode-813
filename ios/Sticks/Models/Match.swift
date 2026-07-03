//
//  Match.swift
//  Sticks
//
//  Match summary shapes returned by GET /matches.
//

import Foundation

nonisolated enum MatchStatus: String, Codable, Hashable {
    case upcoming = "UPCOMING"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
}

/// Seated player as it appears in the match list payload.
nonisolated struct MatchPlayerSummary: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let seat: Int?
}

/// One row of GET /matches.
nonisolated struct MatchSummary: Codable, Identifiable, Hashable {
    let id: String
    let courseName: String
    let scheduledAt: Date
    let status: MatchStatus
    let holes: Int
    let startingHole: Int
    let scoringMode: String
    let format: String
    let players: [MatchPlayerSummary]
}

nonisolated struct MatchesResponse: Codable {
    let matches: [MatchSummary]
}
