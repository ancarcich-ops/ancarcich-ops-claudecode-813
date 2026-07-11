//
//  Match.swift
//  Sticks
//
//  Match summary shapes returned by GET /matches.
//
//  Decoding notes:
//  - scoresByHole arrives as a JSON object with STRING keys ("1": 5),
//    decoded as [String: Int?] and converted to Int keys (matching
//    MatchDetailPlayer's approach).
//  - Every new field is additive and decoded tolerantly with defaults so
//    older payloads keep working.
//

import Foundation

nonisolated enum MatchStatus: String, Codable, Hashable {
    case upcoming = "UPCOMING"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
}

/// Seated player as it appears in the match list payload.
nonisolated struct MatchPlayerSummary: Identifiable, Hashable {
    let id: String
    let displayName: String
    let seat: Int?
    let handicap: Double?
    let avatarUrl: String?
    let avatarSeed: String?
    let avatarVariant: String?
    /// Hole number → strokes (converted from the server's string keys).
    let scoresByHole: [Int: Int]
}

extension MatchPlayerSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, seat, handicap
        case avatarUrl, avatarSeed, avatarVariant, scoresByHole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        seat = try container.decodeIfPresent(Int.self, forKey: .seat)
        handicap = try container.decodeIfPresent(Double.self, forKey: .handicap)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        avatarSeed = try container.decodeIfPresent(String.self, forKey: .avatarSeed)
        avatarVariant = try container.decodeIfPresent(String.self, forKey: .avatarVariant)

        // String keys → Int keys; null values (cleared scores) are dropped.
        let raw = try container.decodeIfPresent([String: Int?].self, forKey: .scoresByHole) ?? [:]
        var converted: [Int: Int] = [:]
        for (key, value) in raw {
            if let hole = Int(key), let strokes = value {
                converted[hole] = strokes
            }
        }
        scoresByHole = converted
    }
}

/// One row of GET /matches.
nonisolated struct MatchSummary: Identifiable, Hashable {
    let id: String
    let courseName: String
    let scheduledAt: Date
    let completedAt: Date?
    let status: MatchStatus
    let holes: Int
    let startingHole: Int
    let scoringMode: String
    let format: String
    /// Exactly `holes` entries, index = round order.
    let pars: [Int]
    /// matchPlayerId → win probability 0..1. May be empty.
    let probabilities: [String: Double]
    let myMatchPlayerId: String?
    /// Group this match was posted to, when any.
    let groupId: String?
    let players: [MatchPlayerSummary]
    /// Server-provided marquee strings for the home-card ticker
    /// ("SEUSS.MD 74%", "LEADER -1 THRU 9", …). Empty when absent.
    let tickerItems: [String]

    /// Absolute hole number for round index `index`, honoring startingHole
    /// with wraparound past 18 (shotgun/back-nine starts).
    func holeNumber(at index: Int) -> Int {
        ((startingHole - 1 + index) % 18) + 1
    }

    /// Par for round index `index` (pars has exactly `holes` entries).
    func par(at index: Int) -> Int {
        guard pars.indices.contains(index) else { return 4 }
        return pars[index]
    }

    /// Round index of the next hole in play — the first hole in round
    /// order where not every player has a score. Falls back to the last
    /// hole when everything is scored.
    var nextHoleIndex: Int {
        guard !players.isEmpty else { return 0 }
        for index in 0 ..< max(holes, 1) {
            let hole = holeNumber(at: index)
            if players.contains(where: { $0.scoresByHole[hole] == nil }) {
                return index
            }
        }
        return max(holes - 1, 0)
    }
}

extension MatchSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, courseName, scheduledAt, completedAt, status, holes
        case startingHole, scoringMode, format, pars, probabilities
        case myMatchPlayerId, groupId, players, tickerItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        courseName = try container.decode(String.self, forKey: .courseName)
        scheduledAt = try container.decode(Date.self, forKey: .scheduledAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decode(MatchStatus.self, forKey: .status)
        holes = try container.decode(Int.self, forKey: .holes)
        startingHole = try container.decode(Int.self, forKey: .startingHole)
        scoringMode = try container.decode(String.self, forKey: .scoringMode)
        format = try container.decode(String.self, forKey: .format)
        pars = try container.decodeIfPresent([Int].self, forKey: .pars) ?? []
        probabilities = try container.decodeIfPresent([String: Double].self, forKey: .probabilities) ?? [:]
        myMatchPlayerId = try container.decodeIfPresent(String.self, forKey: .myMatchPlayerId)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        players = try container.decodeIfPresent([MatchPlayerSummary].self, forKey: .players) ?? []
        tickerItems = try container.decodeIfPresent([String].self, forKey: .tickerItems) ?? []
    }
}

nonisolated struct MatchesResponse: Decodable {
    let matches: [MatchSummary]
}
