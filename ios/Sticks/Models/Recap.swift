//
//  Recap.swift
//  Sticks
//
//  Slice 101: the post-round recap, GET /matches/:id/recap. The server
//  computes everything — naming scores against par, walking the round's
//  real routing, allocating strokes by position, making the per-hole
//  swings sum to the stated margin. The app lays it out.
//
//  `recap` is ALWAYS gross. On a net round `netRecap` carries the same
//  shape scored net; where the two disagree about who won, both results
//  are printed — a recap that implies somebody won a match they lost is
//  worse than no recap.
//
//  Decoded leniently throughout: a section that fails to decode is
//  dropped rather than failing the whole recap.
//

import Foundation

nonisolated struct RoundRecap: Decodable {
    /// Whose card this is — the caller's seat, or the first player's for
    /// a spectator. `history` is null unless it's the caller's own seat.
    let seat: RecapSeat
    let scoringMode: String?
    let headline: RecapHeadline
    /// Always gross.
    let recap: RecapBody
    /// Same shape, scored net. Null on a gross round.
    let netRecap: RecapBody?
    /// Only the caller's own seat — "your average here" means nothing
    /// about somebody else's round.
    let history: RecapHistory?
    let historyLabel: String?

    private enum CodingKeys: String, CodingKey {
        case seat, scoringMode, headline, recap, netRecap, history, historyLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seat = (try? container.decode(RecapSeat.self, forKey: .seat))
            ?? RecapSeat(matchPlayerId: "", displayName: "")
        scoringMode = try? container.decodeIfPresent(String.self, forKey: .scoringMode)
        headline = (try? container.decode(RecapHeadline.self, forKey: .headline))
            ?? RecapHeadline(score: "", toPar: "", story: "")
        recap = (try? container.decode(RecapBody.self, forKey: .recap)) ?? RecapBody.empty
        netRecap = try? container.decodeIfPresent(RecapBody.self, forKey: .netRecap)
        history = try? container.decodeIfPresent(RecapHistory.self, forKey: .history)
        historyLabel = try? container.decodeIfPresent(String.self, forKey: .historyLabel)
    }
}

nonisolated struct RecapSeat: Decodable {
    let matchPlayerId: String
    let displayName: String
}

nonisolated struct RecapHeadline: Decodable {
    let score: String
    let toPar: String
    let story: String
}

/// One section of the recap — `recap` (gross) and `netRecap` (net) share it.
nonisolated struct RecapBody: Decodable {
    let totals: RecapTotals?
    /// Cumulative strokes against par, one point per scored hole, in
    /// PLAYING order — off the tenth this runs 10 … 18, 1 … 9. Never sorted.
    let arc: [RecapArcPoint]
    let best: RecapStretch?
    let worst: RecapStretch?
    let distribution: RecapDistribution?
    let byPar: [RecapByParRow]
    let difficulty: [RecapDifficultyRow]
    let swings: [RecapSwing]

    static let empty = RecapBody()

    private enum CodingKeys: String, CodingKey {
        case totals, arc, best, worst, distribution, byPar, difficulty, swings
    }

    init() {
        totals = nil
        arc = []
        best = nil
        worst = nil
        distribution = nil
        byPar = []
        difficulty = []
        swings = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totals = try? container.decodeIfPresent(RecapTotals.self, forKey: .totals)
        arc = (try? container.decodeIfPresent([RecapArcPoint].self, forKey: .arc)) ?? []
        best = try? container.decodeIfPresent(RecapStretch.self, forKey: .best)
        worst = try? container.decodeIfPresent(RecapStretch.self, forKey: .worst)
        distribution = try? container.decodeIfPresent(RecapDistribution.self, forKey: .distribution)
        byPar = (try? container.decodeIfPresent([RecapByParRow].self, forKey: .byPar)) ?? []
        difficulty = (try? container.decodeIfPresent([RecapDifficultyRow].self, forKey: .difficulty)) ?? []
        swings = (try? container.decodeIfPresent([RecapSwing].self, forKey: .swings)) ?? []
    }
}

nonisolated struct RecapTotals: Decodable {
    let holesScored: Int?
    let gross: Int?
    let net: Int?
    let grossToPar: Int?
    let netToPar: Int?
    /// Front/back nines, when the round has them.
    let front: RecapNine?
    let back: RecapNine?

    nonisolated struct RecapNine: Decodable {
        let gross: Int?
        let net: Int?
        let toPar: Int?
    }
}

/// One point of the arc. `position` is the index in playing order.
nonisolated struct RecapArcPoint: Decodable {
    let hole: Int
    let position: Int
    /// Cumulative strokes against par so far.
    let toPar: Int
    let strokes: Int
    let par: Int
    let delta: Int
}

/// A best/worst stretch. `from`/`to` are INCLUSIVE arc positions —
/// from 6 to 9 with holes 4 = positions 6, 7, 8, 9 (confirmed live:
/// the server returns from 1, to 4, holes 4 for an all-bogeys round).
nonisolated struct RecapStretch: Decodable {
    let from: Int
    let to: Int
    let vsPar: Int
    let holes: Int
}

nonisolated struct RecapDistribution: Decodable {
    let eaglesOrBetter: Int?
    let birdies: Int?
    let pars: Int?
    let bogeys: Int?
    let doubles: Int?
    let triplesOrWorse: Int?
}

nonisolated struct RecapByParRow: Decodable {
    let par: Int
    let holes: Int
    let avgScore: Double?
    let avgVsPar: Double?
}

/// One third of the card's difficulty ranking. `fromIndex`/`toIndex`
/// are 1-based hole indexes — the app renders label + avgVsPar only.
nonisolated struct RecapDifficultyRow: Decodable {
    let label: String
    let holes: Int
    let avgVsPar: Double?
}

/// Where the match was won, against one opponent. `holes` is already
/// sorted nearest finish first (biggest swing first); `total` is the
/// stated margin — positive = the caller ahead. `series` is every
/// compared hole in playing order, for a chart if one is wanted.
nonisolated struct RecapSwing: Decodable {
    let opponentName: String
    let total: Int
    let comparedHoles: Int
    let halved: Int
    let holes: [RecapSwingHole]
    let series: [RecapSwingSeriesPoint]?

    nonisolated struct RecapSwingHole: Decodable {
        let hole: Int
        let position: Int
        let yourStrokes: Int
        let theirStrokes: Int
        let yourLabel: String?
        let theirLabel: String?
        let swing: Int
    }

    nonisolated struct RecapSwingSeriesPoint: Decodable {
        let hole: Int
        let position: Int
        let swing: Int
        let yourVsPar: Int
        let theirVsPar: Int
    }
}

/// "Against your history here" — shape is server-owned, so it decodes
/// leniently into displayable rows. Only ever present for the caller's
/// own seat.
nonisolated struct RecapHistory: Decodable {
    let rows: [Row]

    nonisolated struct Row: Identifiable {
        let key: String
        let value: String
        var id: String { key }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: RecapFlexibleValue].self)
        rows = raw
            .sorted { $0.key < $1.key }
            .map { Row(key: $0.key, value: $0.value.displayText) }
    }
}

/// Any JSON scalar, for the history map.
nonisolated struct RecapFlexibleValue: Decodable {
    let displayText: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            displayText = flag ? "Yes" : "No"
        } else if let number = try? container.decode(Double.self) {
            displayText = number.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(number))
                : String(format: "%.1f", number)
        } else {
            displayText = (try? container.decode(String.self)) ?? ""
        }
    }
}
