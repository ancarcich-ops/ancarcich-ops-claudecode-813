//
//  PlayerStats.swift
//  Sticks
//
//  Shapes for GET /stats — the caller's personal stats plus handicap
//  baselines. Decoded tolerantly (counts default to 0, arrays to [],
//  optionals stay nil) so additive server changes never break clients.
//

import Foundation

/// One completed (or in-progress logged) round in the stats history.
nonisolated struct LoggedRound: Identifiable, Hashable {
    let matchId: String
    let courseName: String
    let scheduledAt: Date?
    let holesPlayed: Int
    let vsPar: Int
    let gross: Int
    /// The match creator's userId — deletes are creator-only.
    let creatorId: String?
    /// Server-computed "the caller created this match" flag.
    let createdByMe: Bool

    var id: String { matchId }
}

extension LoggedRound: Decodable {
    private enum CodingKeys: String, CodingKey {
        case matchId, courseName, scheduledAt, holesPlayed, vsPar, gross
        case creatorId, createdById, createdByMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decode(String.self, forKey: .matchId)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
        holesPlayed = try container.decodeIfPresent(Int.self, forKey: .holesPlayed) ?? 0
        vsPar = try container.decodeIfPresent(Int.self, forKey: .vsPar) ?? 0
        gross = try container.decodeIfPresent(Int.self, forKey: .gross) ?? 0
        if let direct = try container.decodeIfPresent(String.self, forKey: .creatorId) {
            creatorId = direct
        } else {
            creatorId = try container.decodeIfPresent(String.self, forKey: .createdById)
        }
        createdByMe = try container.decodeIfPresent(Bool.self, forKey: .createdByMe) ?? false
    }
}

/// The player's single best round.
nonisolated struct BestRound: Hashable {
    let matchId: String
    let courseName: String
    let scheduledAt: Date?
    let vsPar: Int
    let gross: Int
}

extension BestRound: Decodable {
    private enum CodingKeys: String, CodingKey {
        case matchId, courseName, scheduledAt, vsPar, gross
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decodeIfPresent(String.self, forKey: .matchId) ?? ""
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
        vsPar = try container.decodeIfPresent(Int.self, forKey: .vsPar) ?? 0
        gross = try container.decodeIfPresent(Int.self, forKey: .gross) ?? 0
    }
}

/// Per-par-value scoring bucket (par 3s / 4s / 5s).
nonisolated struct ParBucket: Hashable {
    let holesPlayed: Int
    let avgVsPar: Double?
    let avgScore: Double?
}

extension ParBucket: Decodable {
    private enum CodingKeys: String, CodingKey {
        case holesPlayed, avgVsPar, avgScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        holesPlayed = try container.decodeIfPresent(Int.self, forKey: .holesPlayed) ?? 0
        avgVsPar = try container.decodeIfPresent(Double.self, forKey: .avgVsPar)
        avgScore = try container.decodeIfPresent(Double.self, forKey: .avgScore)
    }

    static let empty = ParBucket(holesPlayed: 0, avgVsPar: nil, avgScore: nil)
}

/// Per-18 normalized distribution counts (also used by baselines).
nonisolated struct DistributionPer18: Hashable {
    let birdiesOrBetter: Double
    let pars: Double
    let bogeys: Double
    let doublesOrWorse: Double

    static let zero = DistributionPer18(birdiesOrBetter: 0, pars: 0, bogeys: 0, doublesOrWorse: 0)
}

extension DistributionPer18: Decodable {
    private enum CodingKeys: String, CodingKey {
        case birdiesOrBetter, pars, bogeys, doublesOrWorse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        birdiesOrBetter = try container.decodeIfPresent(Double.self, forKey: .birdiesOrBetter) ?? 0
        pars = try container.decodeIfPresent(Double.self, forKey: .pars) ?? 0
        bogeys = try container.decodeIfPresent(Double.self, forKey: .bogeys) ?? 0
        doublesOrWorse = try container.decodeIfPresent(Double.self, forKey: .doublesOrWorse) ?? 0
    }
}

/// Raw score distribution across all played holes.
nonisolated struct ScoreDistribution: Hashable {
    let birdiesOrBetter: Int
    let pars: Int
    let bogeys: Int
    let doublesOrWorse: Int
    let totalHolesPlayed: Int
    let per18: DistributionPer18

    static let empty = ScoreDistribution(
        birdiesOrBetter: 0, pars: 0, bogeys: 0, doublesOrWorse: 0,
        totalHolesPlayed: 0, per18: .zero
    )
}

extension ScoreDistribution: Decodable {
    private enum CodingKeys: String, CodingKey {
        case birdiesOrBetter, pars, bogeys, doublesOrWorse, totalHolesPlayed, per18
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        birdiesOrBetter = try container.decodeIfPresent(Int.self, forKey: .birdiesOrBetter) ?? 0
        pars = try container.decodeIfPresent(Int.self, forKey: .pars) ?? 0
        bogeys = try container.decodeIfPresent(Int.self, forKey: .bogeys) ?? 0
        doublesOrWorse = try container.decodeIfPresent(Int.self, forKey: .doublesOrWorse) ?? 0
        totalHolesPlayed = try container.decodeIfPresent(Int.self, forKey: .totalHolesPlayed) ?? 0
        per18 = try container.decodeIfPresent(DistributionPer18.self, forKey: .per18) ?? .zero
    }
}

/// Win counts by game type.
nonisolated struct WinsByGame: Hashable {
    let main: Int
    let stableford: Int
    let skins: Int
    let nassau: Int
    let bbb: Int
    let snake: Int
    let wolf: Int

    static let zero = WinsByGame(main: 0, stableford: 0, skins: 0, nassau: 0, bbb: 0, snake: 0, wolf: 0)
}

extension WinsByGame: Decodable {
    private enum CodingKeys: String, CodingKey {
        case main, stableford, skins, nassau, bbb, snake, wolf
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        main = try container.decodeIfPresent(Int.self, forKey: .main) ?? 0
        stableford = try container.decodeIfPresent(Int.self, forKey: .stableford) ?? 0
        skins = try container.decodeIfPresent(Int.self, forKey: .skins) ?? 0
        nassau = try container.decodeIfPresent(Int.self, forKey: .nassau) ?? 0
        bbb = try container.decodeIfPresent(Int.self, forKey: .bbb) ?? 0
        snake = try container.decodeIfPresent(Int.self, forKey: .snake) ?? 0
        wolf = try container.decodeIfPresent(Int.self, forKey: .wolf) ?? 0
    }
}

/// The player's best round on one course.
nonisolated struct StatsCourseRecord: Identifiable, Hashable {
    let courseName: String
    let gross: Int?
    let net: Double?

    var id: String { courseName }
}

extension StatsCourseRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case courseName, gross, net
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        gross = try container.decodeIfPresent(Int.self, forKey: .gross)
        net = try container.decodeIfPresent(Double.self, forKey: .net)
    }
}

/// One round in the last-20 scoring record, with its handicap
/// differential. `method` is "WHS" (real rating/slope) or "score-only"
/// (estimated — tagged **est** in the UI).
nonisolated struct BreakdownRound: Identifiable, Hashable {
    let matchId: String
    let courseName: String
    let holesPlayed: Int
    let gross: Int
    let vsPar: Int
    let rating: Double?
    let slope: Double?
    let differential: Double
    let method: String
    /// True when this differential counts toward the index (lowest N).
    let used: Bool

    var id: String { matchId + "-" + String(differential) }

    var isEstimated: Bool { method == "score-only" }
}

extension BreakdownRound: Decodable {
    private enum CodingKeys: String, CodingKey {
        case matchId, courseName, holesPlayed, gross, vsPar
        case rating, slope, differential, method, used
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decodeIfPresent(String.self, forKey: .matchId) ?? ""
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        holesPlayed = try container.decodeIfPresent(Int.self, forKey: .holesPlayed) ?? 0
        gross = try container.decodeIfPresent(Int.self, forKey: .gross) ?? 0
        vsPar = try container.decodeIfPresent(Int.self, forKey: .vsPar) ?? 0
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        slope = try container.decodeIfPresent(Double.self, forKey: .slope)
        differential = try container.decodeIfPresent(Double.self, forKey: .differential) ?? 0
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "WHS"
        used = try container.decodeIfPresent(Bool.self, forKey: .used) ?? false
    }
}

/// Wraps an element decode so a single malformed entry drops out of an
/// array instead of failing the whole payload.
nonisolated private struct LossyElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

/// How the Sticks index is built — every round's differential plus the
/// average → adjust → ×0.96 math. The server sends null until the
/// player has 3+ rounds.
nonisolated struct IndexBreakdown: Hashable {
    /// Chronological, one per round in the last-20 scoring record.
    let perRound: [BreakdownRound]
    /// The "best N" differentials that count.
    let usedCount: Int
    /// Strokes subtracted for short records (0 when none).
    let adjust: Double
    /// Mean of the used differentials.
    let average: Double
    /// The bonus-of-excellence multiplier (0.96).
    let factor: Double
    let index: Double
    let fromRounds: Int
    let totalRounds: Int
}

extension IndexBreakdown: Decodable {
    private enum CodingKeys: String, CodingKey {
        case perRound, usedCount, adjust, average, factor, index
        case fromRounds, totalRounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lossy = try container.decodeIfPresent([LossyElement<BreakdownRound>].self, forKey: .perRound) ?? []
        perRound = lossy.compactMap { $0.value }
        usedCount = try container.decodeIfPresent(Int.self, forKey: .usedCount) ?? 0
        adjust = try container.decodeIfPresent(Double.self, forKey: .adjust) ?? 0
        average = try container.decodeIfPresent(Double.self, forKey: .average) ?? 0
        factor = try container.decodeIfPresent(Double.self, forKey: .factor) ?? 0.96
        index = try container.decodeIfPresent(Double.self, forKey: .index) ?? 0
        fromRounds = try container.decodeIfPresent(Int.self, forKey: .fromRounds) ?? 0
        totalRounds = try container.decodeIfPresent(Int.self, forKey: .totalRounds) ?? 0
    }
}

/// The full personal-stats payload.
nonisolated struct PlayerStats {
    let username: String
    let displayName: String
    /// Sticks index — nil until 3 rounds are logged.
    let index: Double?
    let indexFromRounds: Int
    /// Index change over the last 30 days.
    let indexDelta30: Double?
    /// Oldest → newest, ends at the current index.
    let indexTrajectory: [Double]
    let roundsCompleted: Int
    let ghin: String?
    /// The player's self-set index goal — nil when unset.
    let targetIndex: Double?
    let avg18Gross: Double?
    let bestRound: BestRound?
    /// Chronological (oldest first).
    let rounds: [LoggedRound]
    let par3: ParBucket
    let par4: ParBucket
    let par5: ParBucket
    let distribution: ScoreDistribution
    let matchesPlayed: Int
    let totalWins: Int
    let mainWins: Int
    let currentMainStreak: Int
    let bestMainStreak: Int
    let winsByGame: WinsByGame
    let courseRecords: [StatsCourseRecord]
    /// How the index is built — nil until the player has 3+ rounds.
    let indexBreakdown: IndexBreakdown?
}

extension PlayerStats: Decodable {
    private enum CodingKeys: String, CodingKey {
        case username, displayName, index, indexFromRounds, indexDelta30
        case indexTrajectory, roundsCompleted, ghin, targetIndex, avg18Gross, bestRound
        case rounds, par3, par4, par5, distribution
        case matchesPlayed, totalWins, mainWins, currentMainStreak, bestMainStreak
        case winsByGame, courseRecords, indexBreakdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        index = try container.decodeIfPresent(Double.self, forKey: .index)
        indexFromRounds = try container.decodeIfPresent(Int.self, forKey: .indexFromRounds) ?? 0
        indexDelta30 = try container.decodeIfPresent(Double.self, forKey: .indexDelta30)
        indexTrajectory = try container.decodeIfPresent([Double].self, forKey: .indexTrajectory) ?? []
        roundsCompleted = try container.decodeIfPresent(Int.self, forKey: .roundsCompleted) ?? 0
        // GHIN may arrive as a string or a number.
        if let string = try? container.decodeIfPresent(String.self, forKey: .ghin) {
            ghin = string
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .ghin) {
            ghin = String(number)
        } else {
            ghin = nil
        }
        targetIndex = try container.decodeIfPresent(Double.self, forKey: .targetIndex)
        avg18Gross = try container.decodeIfPresent(Double.self, forKey: .avg18Gross)
        bestRound = try container.decodeIfPresent(BestRound.self, forKey: .bestRound)
        rounds = try container.decodeIfPresent([LoggedRound].self, forKey: .rounds) ?? []
        par3 = try container.decodeIfPresent(ParBucket.self, forKey: .par3) ?? .empty
        par4 = try container.decodeIfPresent(ParBucket.self, forKey: .par4) ?? .empty
        par5 = try container.decodeIfPresent(ParBucket.self, forKey: .par5) ?? .empty
        distribution = try container.decodeIfPresent(ScoreDistribution.self, forKey: .distribution) ?? .empty
        matchesPlayed = try container.decodeIfPresent(Int.self, forKey: .matchesPlayed) ?? 0
        totalWins = try container.decodeIfPresent(Int.self, forKey: .totalWins) ?? 0
        mainWins = try container.decodeIfPresent(Int.self, forKey: .mainWins) ?? 0
        currentMainStreak = try container.decodeIfPresent(Int.self, forKey: .currentMainStreak) ?? 0
        bestMainStreak = try container.decodeIfPresent(Int.self, forKey: .bestMainStreak) ?? 0
        winsByGame = try container.decodeIfPresent(WinsByGame.self, forKey: .winsByGame) ?? .zero
        courseRecords = try container.decodeIfPresent([StatsCourseRecord].self, forKey: .courseRecords) ?? []
        indexBreakdown = (try? container.decodeIfPresent(IndexBreakdown.self, forKey: .indexBreakdown)) ?? nil
    }
}

/// One handicap baseline for the scoring-analysis comparisons.
nonisolated struct StatsBaseline: Identifiable, Hashable {
    nonisolated struct AvgScores: Hashable {
        let par3: Double
        let par4: Double
        let par5: Double
    }

    let hcp: Int
    let avgScores: AvgScores
    let distribution: DistributionPer18

    var id: Int { hcp }
}

extension StatsBaseline.AvgScores: Decodable {
    private enum CodingKeys: String, CodingKey {
        case par3, par4, par5
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        par3 = try container.decodeIfPresent(Double.self, forKey: .par3) ?? 0
        par4 = try container.decodeIfPresent(Double.self, forKey: .par4) ?? 0
        par5 = try container.decodeIfPresent(Double.self, forKey: .par5) ?? 0
    }
}

extension StatsBaseline: Decodable {
    private enum CodingKeys: String, CodingKey {
        case hcp, avgScores, distribution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hcp = try container.decodeIfPresent(Int.self, forKey: .hcp) ?? 0
        avgScores = try container.decodeIfPresent(AvgScores.self, forKey: .avgScores)
            ?? AvgScores(par3: 0, par4: 0, par5: 0)
        distribution = try container.decodeIfPresent(DistributionPer18.self, forKey: .distribution) ?? .zero
    }
}

nonisolated struct StatsResponse: Decodable {
    let stats: PlayerStats
    let baselines: [StatsBaseline]
    /// True when a /users/:username/stats lookup resolved to the caller
    /// (route those to the editable Stats tab). Absent on /stats —
    /// defaults false.
    let isSelf: Bool
    /// Slice 68: my follow relationship to this profile — "none" /
    /// "pending" / "accepted". Absent on /stats and older servers.
    let followState: String?
    /// Slice 68: the profile's userId — the target for follow actions.
    let targetUserId: String?

    private enum CodingKeys: String, CodingKey {
        case stats, baselines, isSelf, followState, targetUserId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stats = try container.decode(PlayerStats.self, forKey: .stats)
        baselines = try container.decodeIfPresent([StatsBaseline].self, forKey: .baselines) ?? []
        isSelf = (try? container.decodeIfPresent(Bool.self, forKey: .isSelf)) ?? false
        followState = try? container.decodeIfPresent(String.self, forKey: .followState)
        targetUserId = try? container.decodeIfPresent(String.self, forKey: .targetUserId)
    }
}
