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

// MARK: - Format (slice 83)

/// How a tournament is scored — one of the server's format registry
/// entries (GET /formats). The server resolves legacy tournaments to a
/// real format, so this is never absent on a tournament payload.
///
/// Field meanings (spec appendix A):
/// - `teamSize`: players per side; nil = individual play.
/// - `entry`: `.shared` = one card per hole for the side (scramble);
///   `.perPlayer` = everyone keeps their own card.
/// - `countBest`: balls counted per hole; nil = every ball, summed.
/// - `result`: `.strokes` (low wins) or `.points` (Stableford, high wins).
nonisolated struct TournamentFormat: Hashable {
    nonisolated enum Entry: Hashable {
        case shared
        case perPlayer
    }

    nonisolated enum Result: Hashable {
        case strokes
        case points
    }

    let id: String
    let label: String
    let blurb: String?
    let teamSize: Int?
    let entry: Entry
    let countBest: Int?
    let result: Result

    /// True when players are grouped into sides.
    var isTeamFormat: Bool { (teamSize ?? 1) > 1 }
    /// Scramble-style: the side records one score per hole.
    var isSharedCard: Bool { entry == .shared }
    /// Stableford: higher totals are better.
    var highWins: Bool { result == .points }
}

extension TournamentFormat: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, label, blurb, teamSize, entry, countBest, result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        blurb = try? container.decodeIfPresent(String.self, forKey: .blurb)
        teamSize = try? container.decodeIfPresent(Int.self, forKey: .teamSize)
        // The list endpoint sends only id/label/teamSize — the rest
        // default to the per-player / low-wins reading.
        let rawEntry = (try? container.decodeIfPresent(String.self, forKey: .entry)) ?? nil
        entry = rawEntry?.lowercased() == "shared" ? .shared : .perPlayer
        countBest = try? container.decodeIfPresent(Int.self, forKey: .countBest)
        let rawResult = (try? container.decodeIfPresent(String.self, forKey: .result)) ?? nil
        result = rawResult?.lowercased() == "points" ? .points : .strokes
    }
}

// MARK: - GET /formats (slice 84)

extension TournamentFormat: Identifiable {}

/// One side-size bucket of the GET /formats registry — e.g. size 2,
/// "2-man teams", with that size's six formats.
nonisolated struct FormatGroup: Identifiable, Hashable {
    let size: Int
    let label: String
    let formats: [TournamentFormat]

    var id: Int { size }
}

extension FormatGroup: Decodable {
    private enum CodingKeys: String, CodingKey {
        case size, label, formats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 1
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        formats = ((try? container.decode([Lenient<TournamentFormat>].self, forKey: .formats)) ?? [])
            .compactMap(\.value)
    }

    /// Wrapper so one malformed entry never sinks the registry.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }
}

/// GET /formats — the full format registry. Drives the
/// create-tournament picker; never hard-code a copy of this list.
nonisolated struct FormatsResponse: Decodable {
    let groups: [FormatGroup]

    private enum CodingKeys: String, CodingKey { case groups }

    /// Wrapper so one malformed group never sinks the registry.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = ((try? container.decodeIfPresent([Lenient<FormatGroup>].self, forKey: .groups)) ?? [])
            .compactMap(\.value)
            .sorted { $0.size < $1.size }
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
    /// id / label / teamSize only on list rows.
    let format: TournamentFormat
}

extension TournamentSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, status, scoringMode, roundsPlanned, roundsPlayed
        case playerCount, isCreator, inviteCode, createdAt, format
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
        format = try container.decode(TournamentFormat.self, forKey: .format)
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
    let format: TournamentFormat
}

extension TournamentInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, status, scoringMode, roundsPlanned
        case scheduledStartAt, notes, inviteCode, isCreator, createdBy, format
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
        format = try container.decode(TournamentFormat.self, forKey: .format)
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

/// One roster entry on the detail payload. `team` is nil for an
/// unseated player (slices 85/86); `partnerName` is the entry's
/// requested partner, shown in the teams screen as a seating hint.
nonisolated struct TournamentRosterEntry: Identifiable, Hashable {
    let id: String
    let displayName: String
    let userId: String?
    let handicapAtStart: Double?
    let team: Int?
    let partnerName: String?
}

extension TournamentRosterEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, userId, handicapAtStart, team, partnerName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Player"
        userId = try? container.decodeIfPresent(String.self, forKey: .userId)
        handicapAtStart = try? container.decodeIfPresent(Double.self, forKey: .handicapAtStart)
        team = try? container.decodeIfPresent(Int.self, forKey: .team)
        partnerName = try? container.decodeIfPresent(String.self, forKey: .partnerName)
    }
}

// MARK: - Sides (slice 85)

/// One member of a formed side on the detail payload.
nonisolated struct TournamentTeamMember: Identifiable, Hashable {
    let rosterId: String
    let displayName: String
    let userId: String?
    let handicap: Double?

    var id: String { rosterId }
}

extension TournamentTeamMember: Decodable {
    private enum CodingKeys: String, CodingKey {
        case rosterId, displayName, userId, handicap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rosterId = try container.decodeIfPresent(String.self, forKey: .rosterId) ?? UUID().uuidString
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Player"
        userId = try? container.decodeIfPresent(String.self, forKey: .userId)
        handicap = try? container.decodeIfPresent(Double.self, forKey: .handicap)
    }
}

/// One formed side. `complete: false` means fewer players than the
/// format needs — show it as incomplete, not as a normal side.
nonisolated struct TournamentSide: Identifiable, Hashable {
    let team: Int
    let members: [TournamentTeamMember]
    let complete: Bool

    var id: Int { team }
}

extension TournamentSide: Decodable {
    private enum CodingKeys: String, CodingKey {
        case team, members, complete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        team = try container.decodeIfPresent(Int.self, forKey: .team) ?? 0
        members = ((try? container.decode([Lenient<TournamentTeamMember>].self, forKey: .members)) ?? [])
            .compactMap(\.value)
        complete = try container.decodeIfPresent(Bool.self, forKey: .complete) ?? false
    }

    /// Wrapper so one malformed member never sinks the side.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
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
    /// Formed sides, already in team-number order (slice 85). Empty
    /// when the event hasn't been seeded into sides.
    let teams: [TournamentSide]

    private enum CodingKeys: String, CodingKey {
        case tournament, rounds, roster, leaderboard, odds, teams
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
        teams = ((try? container.decode([Lenient<TournamentSide>].self, forKey: .teams)) ?? [])
            .compactMap(\.value)
    }
}

// MARK: - Team mutations (slice 86)

/// Body for POST /tournaments/:id/teams — ROSTER ENTRY ids
/// (roster[].id), not user ids.
nonisolated struct FormTeamRequest: Encodable {
    let playerIds: [String]
}

/// Accepts any response shape — the teams screen refetches the detail
/// after every mutation rather than trusting the mutation body.
nonisolated struct TournamentMutationResponse: Decodable {
    init(from decoder: Decoder) throws {}
}

/// POST /tournaments/:id/teams/auto — auto-seating honours MUTUAL
/// partner requests only. Left-over players stay unassigned rather
/// than landing on a short side the format can't score.
nonisolated struct AutoSeatResponse: Decodable {
    let formed: Int
    let leftOver: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formed = try container.decodeIfPresent(Int.self, forKey: .formed) ?? 0
        leftOver = try container.decodeIfPresent(Int.self, forKey: .leftOver) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case formed, leftOver
    }
}

// MARK: - POST /tournaments

/// Body for POST /tournaments — optional keys are dropped when nil
/// (synthesized Encodable omits nil keys, which the server expects).
nonisolated struct CreateTournamentRequest: Encodable {
    let name: String
    /// An id from GET /formats. Nil is omitted — the server then falls
    /// back to its legacy scoring. Unknown ids are dropped server-side,
    /// never rejected.
    let format: String?
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
