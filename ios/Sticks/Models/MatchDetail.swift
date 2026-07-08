//
//  MatchDetail.swift
//  Sticks
//
//  Full match payload from GET /matches/:id.
//
//  Decoding notes:
//  - scoresByHole / holeGeo / hazards arrive as JSON objects with STRING
//    keys ("1": 5). They are decoded as [String: …] and converted to Int
//    keys afterward — decoding [Int: …] directly would fail because Swift's
//    Codable expects a JSON array for Int-keyed dictionaries.
//  - Every geo field can be null server-side, so all HoleGeo fields are
//    optionals and the UI must degrade gracefully.
//

import Foundation

nonisolated struct GeoPoint: Codable, Hashable {
    let lat: Double
    let lng: Double
}

nonisolated enum HazardKind: String, Codable, Hashable {
    case water = "WATER"
    case sand = "SAND"
    case oob = "OOB"
    case other = "OTHER"

    /// Tolerant decoding — unknown kinds map to `.other`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HazardKind(rawValue: raw) ?? .other
    }
}

nonisolated struct Hazard: Codable, Hashable {
    let kind: HazardKind
    let label: String?
    let lat: Double?
    let lng: Double?
}

/// Course wind conditions — null when unavailable.
nonisolated struct Wind: Codable, Hashable {
    let speedMph: Double
    /// Compass direction the wind blows FROM, in degrees.
    let fromDeg: Double
}

/// Per-hole GPS geometry. ANY field can be null.
nonisolated struct HoleGeo: Codable, Hashable {
    let hole: Int?
    let teeLat: Double?
    let teeLng: Double?
    let greenLat: Double?
    let greenLng: Double?
    let greenFrontLat: Double?
    let greenFrontLng: Double?
    let greenBackLat: Double?
    let greenBackLng: Double?
    let greenPolygon: [GeoPoint]?
    let fairwayPolygon: [GeoPoint]?
    let distanceYds: Double?
    let source: String?
}

/// Seated player with scores, as returned by GET /matches/:id.
nonisolated struct MatchDetailPlayer: Identifiable, Hashable {
    let id: String
    let userId: String?
    let displayName: String
    let handicap: Double?
    let seat: Int?
    let team: String?
    /// Hole number → strokes (converted from the server's string keys).
    /// Mutable so score posts can update the scorecard optimistically.
    var scoresByHole: [Int: Int]
}

extension MatchDetailPlayer: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, userId, displayName, handicap, seat, team, scoresByHole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        handicap = try container.decodeIfPresent(Double.self, forKey: .handicap)
        seat = try container.decodeIfPresent(Int.self, forKey: .seat)

        // team may be a string, a number, or null.
        if let teamString = try? container.decode(String.self, forKey: .team) {
            team = teamString
        } else if let teamInt = try? container.decode(Int.self, forKey: .team) {
            team = String(teamInt)
        } else {
            team = nil
        }

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

nonisolated struct MatchDetail: Decodable, Identifiable, Hashable {
    let id: String
    let courseName: String
    let scheduledAt: Date
    let status: MatchStatus
    let holes: Int
    let startingHole: Int
    let scoringMode: String
    let format: String
    let isCreator: Bool
    let myMatchPlayerId: String?
    let pars: [Int]
    var players: [MatchDetailPlayer]

    /// Score entry is allowed if the caller is seated or created the match.
    var canEnterScores: Bool { myMatchPlayerId != nil || isCreator }

    /// Absolute hole number for scorecard column `index`, honoring
    /// startingHole with wraparound past 18 (shotgun/back-nine starts).
    func holeNumber(at index: Int) -> Int {
        ((startingHole - 1 + index) % 18) + 1
    }

    /// Par for scorecard column `index` (pars has exactly `holes` entries).
    func par(at index: Int) -> Int {
        guard pars.indices.contains(index) else { return 4 }
        return pars[index]
    }
}

/// Win probabilities keyed by matchPlayerId (0..1). Absent or empty
/// when the server has no live odds for the match.
nonisolated struct MatchOdds: Decodable, Hashable {
    let probabilities: [String: Double]

    private enum CodingKeys: String, CodingKey { case probabilities }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        probabilities = (try? container.decode([String: Double].self, forKey: .probabilities)) ?? [:]
    }
}

/// One row of a side-game leaderboard. `value` is pre-formatted by the
/// server and displayed verbatim.
nonisolated struct SideGameRow: Decodable, Hashable {
    let playerId: String
    let player: String
    let value: String
    let numeric: Double?
    let isLeader: Bool

    private enum CodingKeys: String, CodingKey {
        case playerId, player, value, numeric, isLeader
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = (try? container.decode(String.self, forKey: .playerId)) ?? ""
        player = (try? container.decode(String.self, forKey: .player)) ?? ""
        value = (try? container.decode(String.self, forKey: .value)) ?? "—"
        numeric = try? container.decode(Double.self, forKey: .numeric)
        isLeader = (try? container.decode(Bool.self, forKey: .isLeader)) ?? false
    }
}

nonisolated struct SideGameLeaderboard: Decodable, Hashable, Identifiable {
    let key: String
    let kind: String
    let title: String
    let subtitle: String?
    let rows: [SideGameRow]

    var id: String { key.isEmpty ? title : key }

    private enum CodingKeys: String, CodingKey {
        case key, kind, title, subtitle, rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        kind = (try? container.decode(String.self, forKey: .kind)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        subtitle = try? container.decode(String.self, forKey: .subtitle)
        rows = (try? container.decode([SideGameRow].self, forKey: .rows)) ?? []
    }
}

/// A side game attached to the match — SKINS, NASSAU, WOLF, etc. — with
/// its pre-computed leaderboards.
nonisolated struct SideGame: Decodable, Hashable, Identifiable {
    let kind: String
    let leaderboards: [SideGameLeaderboard]

    var id: String { kind }

    private enum CodingKeys: String, CodingKey { case kind, leaderboards }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? container.decode(String.self, forKey: .kind)) ?? ""
        leaderboards = (try? container.decode([SideGameLeaderboard].self, forKey: .leaderboards)) ?? []
    }
}

nonisolated struct MatchDetailResponse: Decodable {
    var match: MatchDetail
    /// Keyed by absolute hole number (converted from string keys).
    let holeGeo: [Int: HoleGeo]
    /// Keyed by absolute hole number; holes without hazards are absent.
    let hazards: [Int: [Hazard]]
    /// Wind conditions — nil when the server has none.
    let wind: Wind?
    /// Live win odds — nil/empty when the server has none (solo rounds).
    let odds: MatchOdds?
    /// Side games with pre-computed leaderboards — empty when none.
    let sideGames: [SideGame]

    private enum CodingKeys: String, CodingKey {
        case match, holeGeo, hazards, wind, odds, sideGames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decode(MatchDetail.self, forKey: .match)

        // uniquingKeysWith: keys like "1" and "01" both map to 1 —
        // Dictionary(uniqueKeysWithValues:) would trap on that.
        let rawGeo = try container.decodeIfPresent([String: HoleGeo].self, forKey: .holeGeo) ?? [:]
        holeGeo = Dictionary(rawGeo.compactMap { key, value in
            Int(key).map { ($0, value) }
        }, uniquingKeysWith: { first, _ in first })

        let rawHazards = try container.decodeIfPresent([String: [Hazard]].self, forKey: .hazards) ?? [:]
        hazards = Dictionary(rawHazards.compactMap { key, value in
            Int(key).map { ($0, value) }
        }, uniquingKeysWith: { first, _ in first })

        wind = try container.decodeIfPresent(Wind.self, forKey: .wind)
        odds = try? container.decode(MatchOdds.self, forKey: .odds)
        sideGames = (try? container.decode([SideGame].self, forKey: .sideGames)) ?? []
    }
}
