//
//  Tournament.swift
//  Sticks
//
//  Slice 55: shapes for the tournaments feature — GET /tournaments,
//  GET /tournaments/:id, POST /tournaments, POST /tournaments/join.
//  Everything decodes tolerantly (defaults on optional/collection
//  fields) so additive server changes never break older clients.
//

import Foundation

// MARK: - Status

/// Normalized tournament status — the server sends strings like
/// UPCOMING / LIVE / IN_PROGRESS / FINAL / COMPLETED; anything
/// unrecognized lands on Upcoming.
nonisolated enum TournamentStatus: Hashable {
    case upcoming
    case live
    case final

    init(raw: String) {
        switch raw.uppercased() {
        case "LIVE", "IN_PROGRESS", "ACTIVE":
            self = .live
        case "FINAL", "COMPLETED", "COMPLETE", "FINISHED":
            self = .final
        default:
            self = .upcoming
        }
    }
}

// MARK: - GET /tournaments

/// One row of GET /tournaments.
nonisolated struct TournamentSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let status: TournamentStatus
    let scoringMode: String
    let roundsPlanned: Int
    let roundsPlayed: Int
    let playerCount: Int
    let isCreator: Bool
    let inviteCode: String
    let createdAt: Date?
}

extension TournamentSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, status, scoringMode, roundsPlanned, roundsPlayed
        case playerCount, isCreator, inviteCode, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = TournamentStatus(raw: (try? container.decode(String.self, forKey: .status)) ?? "")
        scoringMode = try container.decodeIfPresent(String.self, forKey: .scoringMode) ?? "NET"
        roundsPlanned = try container.decodeIfPresent(Int.self, forKey: .roundsPlanned) ?? 1
        roundsPlayed = try container.decodeIfPresent(Int.self, forKey: .roundsPlayed) ?? 0
        playerCount = try container.decodeIfPresent(Int.self, forKey: .playerCount) ?? 0
        isCreator = try container.decodeIfPresent(Bool.self, forKey: .isCreator) ?? false
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

nonisolated struct TournamentsResponse: Decodable {
    let tournaments: [TournamentSummary]

    private enum CodingKeys: String, CodingKey {
        case tournaments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tournaments = try container.decodeIfPresent([TournamentSummary].self, forKey: .tournaments) ?? []
    }
}

// MARK: - GET /tournaments/:id

/// The `tournament` object on the detail payload.
nonisolated struct TournamentInfo {
    let id: String
    let name: String
    let status: TournamentStatus
    let scoringMode: String
    let roundsPlanned: Int
    let scheduledStartAt: Date?
    let notes: String?
    let inviteCode: String
    let isCreator: Bool
    let createdBy: String?
}

extension TournamentInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, status, scoringMode, roundsPlanned
        case scheduledStartAt, notes, inviteCode, isCreator, createdBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = TournamentStatus(raw: (try? container.decode(String.self, forKey: .status)) ?? "")
        scoringMode = try container.decodeIfPresent(String.self, forKey: .scoringMode) ?? "NET"
        roundsPlanned = try container.decodeIfPresent(Int.self, forKey: .roundsPlanned) ?? 1
        scheduledStartAt = try? container.decodeIfPresent(Date.self, forKey: .scheduledStartAt)
        notes = try? container.decodeIfPresent(String.self, forKey: .notes)
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        isCreator = try container.decodeIfPresent(Bool.self, forKey: .isCreator) ?? false
        createdBy = try? container.decodeIfPresent(String.self, forKey: .createdBy)
    }
}

/// One bound round on the detail payload. `players` arrives in an
/// unspecified shape (names, objects, or a count) — decoded leniently
/// into a count + best-effort names, never failing the parent.
nonisolated struct TournamentRound: Identifiable, Hashable {
    let id: String
    let roundNumber: Int
    let courseName: String
    let status: MatchStatus
    let scheduledAt: Date?
    let playerCount: Int
    let playerNames: [String]
}

extension TournamentRound: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, roundNumber, courseName, status, scheduledAt, players
    }

    private struct LenientPlayer: Decodable {
        let displayName: String?
        let name: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        roundNumber = try container.decodeIfPresent(Int.self, forKey: .roundNumber) ?? 0
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? "Round"
        let rawStatus = (try? container.decode(String.self, forKey: .status)) ?? ""
        status = MatchStatus(rawValue: rawStatus.uppercased()) ?? {
            switch TournamentStatus(raw: rawStatus) {
            case .live: return .inProgress
            case .final: return .completed
            case .upcoming: return .upcoming
            }
        }()
        scheduledAt = try? container.decodeIfPresent(Date.self, forKey: .scheduledAt)

        if let names = try? container.decode([String].self, forKey: .players) {
            playerNames = names
            playerCount = names.count
        } else if let objects = try? container.decode([LenientPlayer].self, forKey: .players) {
            let names = objects.compactMap { $0.displayName ?? $0.name }
            playerNames = names
            playerCount = objects.count
        } else if let count = try? container.decode(Int.self, forKey: .players) {
            playerNames = []
            playerCount = count
        } else {
            playerNames = []
            playerCount = 0
        }
    }
}

/// One roster entry on the detail payload.
nonisolated struct TournamentRosterEntry: Identifiable, Hashable {
    let id: String
    let displayName: String
    let userId: String?
    let handicapAtStart: Double?
}

extension TournamentRosterEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, userId, handicapAtStart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Player"
        userId = try? container.decodeIfPresent(String.self, forKey: .userId)
        handicapAtStart = try? container.decodeIfPresent(Double.self, forKey: .handicapAtStart)
    }
}

/// One cumulative-leaderboard row. Scores decode as Double for
/// net-mode tolerance; nulls mark DNP/unfinished rounds.
nonisolated struct TournamentLeaderboardRow: Identifiable, Hashable {
    let rank: Int
    let playerId: String
    let displayName: String
    let latestHandicap: Double?
    let roundScores: [Double?]
    let total: Double?
    let playedRounds: Int

    var id: String { playerId }
}

extension TournamentLeaderboardRow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case rank, playerId, displayName, latestHandicap
        case roundScores, total, playedRounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        playerId = try container.decodeIfPresent(String.self, forKey: .playerId) ?? UUID().uuidString
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Player"
        latestHandicap = try? container.decodeIfPresent(Double.self, forKey: .latestHandicap)
        roundScores = (try? container.decode([Double?].self, forKey: .roundScores)) ?? []
        total = try? container.decodeIfPresent(Double.self, forKey: .total)
        playedRounds = try container.decodeIfPresent(Int.self, forKey: .playedRounds) ?? 0
    }
}

/// One row of the detail's `odds` array, ranked by win probability.
nonisolated struct TournamentOddsRow: Identifiable, Hashable {
    let rank: Int
    let displayName: String
    let latestHandicap: Double?
    let roundScores: [Double?]
    let scoreSoFar: Double?
    let playedRounds: Int
    let roundsPlanned: Int
    let projectedTotal: Double?
    let winProbability: Double

    var id: String { "\(rank)|\(displayName)" }
}

extension TournamentOddsRow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case rank, displayName, latestHandicap, roundScores, scoreSoFar
        case playedRounds, roundsPlanned, projectedTotal, winProbability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Player"
        latestHandicap = try? container.decodeIfPresent(Double.self, forKey: .latestHandicap)
        roundScores = (try? container.decode([Double?].self, forKey: .roundScores)) ?? []
        scoreSoFar = try? container.decodeIfPresent(Double.self, forKey: .scoreSoFar)
        playedRounds = try container.decodeIfPresent(Int.self, forKey: .playedRounds) ?? 0
        roundsPlanned = try container.decodeIfPresent(Int.self, forKey: .roundsPlanned) ?? 0
        projectedTotal = try? container.decodeIfPresent(Double.self, forKey: .projectedTotal)
        winProbability = try container.decodeIfPresent(Double.self, forKey: .winProbability) ?? 0
    }
}

/// Full payload of GET /tournaments/:id. Any malformed row in the
/// collections is dropped rather than failing the whole response.
nonisolated struct TournamentDetailResponse: Decodable {
    let tournament: TournamentInfo
    let rounds: [TournamentRound]
    let roster: [TournamentRosterEntry]
    let leaderboard: [TournamentLeaderboardRow]
    let odds: [TournamentOddsRow]

    private enum CodingKeys: String, CodingKey {
        case tournament, rounds, roster, leaderboard, odds
    }

    /// Wrapper so one bad element never sinks the array.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tournament = try container.decode(TournamentInfo.self, forKey: .tournament)
        rounds = ((try? container.decode([Lenient<TournamentRound>].self, forKey: .rounds)) ?? [])
            .compactMap(\.value)
        roster = ((try? container.decode([Lenient<TournamentRosterEntry>].self, forKey: .roster)) ?? [])
            .compactMap(\.value)
        leaderboard = ((try? container.decode([Lenient<TournamentLeaderboardRow>].self, forKey: .leaderboard)) ?? [])
            .compactMap(\.value)
        odds = ((try? container.decode([Lenient<TournamentOddsRow>].self, forKey: .odds)) ?? [])
            .compactMap(\.value)
    }
}

// MARK: - POST /tournaments

/// Body for POST /tournaments — optional keys are dropped when nil
/// (synthesized Encodable omits nil keys, which the server expects).
nonisolated struct CreateTournamentRequest: Encodable {
    let name: String
    let scoringMode: String?
    let roundsPlanned: Int?
    let scheduledStartAt: String?
    let notes: String?
}

nonisolated struct CreatedTournament: Decodable {
    let id: String
    let inviteCode: String?
}

nonisolated struct CreateTournamentResponse: Decodable {
    let tournament: CreatedTournament
}

// MARK: - POST /tournaments/join

/// Body for POST /tournaments/join — nil handicap is omitted.
nonisolated struct JoinTournamentRequest: Encodable {
    let code: String
    let handicap: Double?
}

nonisolated struct JoinedTournament: Decodable {
    let id: String
}

nonisolated struct JoinTournamentResponse: Decodable {
    let tournament: JoinedTournament
}
