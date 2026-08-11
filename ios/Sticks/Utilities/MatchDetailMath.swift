//
//  MatchDetailMath.swift
//  Sticks
//
//  Slice 13: pure standings math shared by the match-detail hero and
//  standings cards. All sums run in ROUND order (a back-9 start makes
//  hole 10 "front"), matching the web app.
//

import Foundation

nonisolated enum MatchDetailMath {
    /// True for any scoring mode other than GROSS — NET column shows and
    /// ranking uses net.
    static func isNetMode(_ detail: MatchDetail) -> Bool {
        detail.scoringMode.uppercased() != "GROSS"
    }

    /// GROSS Σ(strokes − par) over the player's scored holes within the
    /// given round-index range (whole round when nil). nil when none of
    /// those holes are scored.
    static func grossToPar(
        for player: MatchDetailPlayer,
        in detail: MatchDetail,
        indices: Range<Int>? = nil
    ) -> Int? {
        var diff = 0
        var played = 0
        for index in indices ?? 0 ..< detail.holes {
            guard let strokes = player.scoresByHole[detail.holeNumber(at: index)] else { continue }
            diff += strokes - detail.par(at: index)
            played += 1
        }
        return played > 0 ? diff : nil
    }

    /// Count of holes the player has scored this round.
    static func holesPlayed(for player: MatchDetailPlayer, in detail: MatchDetail) -> Int {
        (0 ..< detail.holes)
            .filter { player.scoresByHole[detail.holeNumber(at: $0)] != nil }
            .count
    }

    /// The whole number of strokes a player receives over a round of
    /// `holes`, from their 18-hole handicap.
    ///
    /// A handicap is an 18-hole figure: play nine and you get half of it.
    /// Rounding to a whole stroke matters too — you cannot receive 0.6 of a
    /// shot on a hole, and a fraction left the card disagreeing with the
    /// total. Half-strokes round up, per WHS.
    ///
    /// Mirrors playingAllowance on the server exactly.
    static func playingAllowance(handicap: Double, holes: Int) -> Int {
        guard handicap > 0, holes > 0, handicap.isFinite else { return 0 }
        return Int((handicap * Double(holes) / 18.0).rounded())
    }

    /// Strokes received on the hole at 0-based round position `index`.
    /// Allocates the round allowance against the course stroke index when we
    /// have a complete one, otherwise spreads it evenly with the remainder on
    /// the opening holes. Summed over the round this returns exactly the
    /// allowance — which is what lets a net total be computed as
    /// `gross - playingAllowance(...)` and still agree with the cells.
    ///
    /// Mirrors strokesGivenForHole on the server exactly.
    static func strokesReceived(
        handicap: Double,
        at index: Int,
        holes: Int,
        strokeIndex: [Int]
    ) -> Int {
        let allowance = playingAllowance(handicap: handicap, holes: holes)
        guard allowance > 0, holes > 0 else { return 0 }
        let base = allowance / holes           // integer division
        let extra = allowance - base * holes

        if strokeIndex.count == holes, strokeIndex.indices.contains(index) {
            let si = strokeIndex[index]
            if si >= 1 && si <= holes {
                return base + (si <= extra ? 1 : 0)
            }
        }
        return base + (index < extra ? 1 : 0)
    }

    /// NET = gross-to-par minus the strokes actually received on the holes
    /// played so far. Matches the web, which sums per-hole allocations
    /// rather than pro-rating the handicap.
    static func netToPar(for player: MatchDetailPlayer, in detail: MatchDetail) -> Double? {
        guard detail.holes > 0,
              let gross = grossToPar(for: player, in: detail) else { return nil }
        let handicap = player.handicap ?? 0
        var received = 0
        for index in 0 ..< detail.holes
        where player.scoresByHole[detail.holeNumber(at: index)] != nil {
            received += strokesReceived(
                handicap: handicap,
                at: index,
                holes: detail.holes,
                strokeIndex: detail.strokeIndex
            )
        }
        return Double(gross - received)
    }

    /// Ranking metric — net in net modes, gross otherwise; players with
    /// no scores rank as even (0).
    static func rankMetric(for player: MatchDetailPlayer, in detail: MatchDetail) -> Double {
        if isNetMode(detail) {
            return netToPar(for: player, in: detail) ?? 0
        }
        return Double(grossToPar(for: player, in: detail) ?? 0)
    }

    /// 1-based rank among all players by the mode's metric, lowest best;
    /// ties share the lower rank. nil when the player isn't in the match.
    static func position(of playerId: String, in detail: MatchDetail) -> Int? {
        guard let me = detail.players.first(where: { $0.id == playerId }) else { return nil }
        let mine = rankMetric(for: me, in: detail)
        let better = detail.players.filter { rankMetric(for: $0, in: detail) < mine - 0.000001 }.count
        return better + 1
    }

    /// Players sorted for standings — by the mode's metric ascending,
    /// ties broken by seat.
    static func rankedPlayers(in detail: MatchDetail) -> [MatchDetailPlayer] {
        detail.players.sorted { a, b in
            let aMetric = rankMetric(for: a, in: detail)
            let bMetric = rankMetric(for: b, in: detail)
            if aMetric != bMetric { return aMetric < bMetric }
            return (a.seat ?? Int.max) < (b.seat ?? Int.max)
        }
    }

    /// "-2" / "+3" / "E" / "—".
    static func toParLabel(_ diff: Int?) -> String {
        guard let diff else { return "—" }
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    /// "-2" / "+3" / "E" / "—" — net is a whole number now that it sums
    /// per-hole received strokes (slices 77/78), so no decimal.
    static func netLabel(_ net: Double?) -> String {
        guard let net else { return "—" }
        if abs(net) < 0.05 { return "E" }
        return String(format: "%+d", Int(net.rounded()))
    }

    /// "st" / "nd" / "rd" / "th" (11–13 are always "th").
    static func ordinalSuffix(_ value: Int) -> String {
        if (11 ... 13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// Canonical key for a side-game kind — the server uses a couple of
    /// aliases for the same games across endpoints.
    static func eventGameKey(_ kind: String) -> String {
        switch kind.uppercased() {
        case "BINGO_BANGO_BONGO": return "BBB"
        case "MATCH_PLAY": return "MATCH"
        default: return kind.uppercased()
        }
    }

    /// True for side games whose state comes from recorded per-hole
    /// events (Snake 3-putts, BBB awards, Match presses, Wolf picks)
    /// rather than the scorecard alone.
    static func isEventDriven(_ kind: String) -> Bool {
        ["SNAKE", "BBB", "MATCH", "WOLF"].contains(eventGameKey(kind))
    }

    /// True when the app has a native editor for the game — the
    /// event-driven games plus config-only Targets (slice 53).
    static func hasNativeEditor(_ kind: String) -> Bool {
        isEventDriven(kind) || eventGameKey(kind) == "TARGETS"
    }

    /// Segmented-tab label for a side-game kind.
    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "SKINS": return "Skins"
        case "STABLEFORD": return "Stbl"
        case "NASSAU": return "Nassau"
        case "WOLF": return "Wolf"
        case "SNAKE": return "Snake"
        case "BBB": return "BBB"
        case "MATCH": return "Match"
        case "SIXES": return "Sixes"
        case "TEAM_VS_TEAM": return "Teams"
        case "TARGETS": return "Targets"
        default: return kind.capitalized
        }
    }
}
