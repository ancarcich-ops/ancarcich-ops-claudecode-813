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

    /// NET = round1( gross − handicap × (holesPlayed / totalHoles) ) —
    /// one decimal. nil when the player has no scores.
    static func netToPar(for player: MatchDetailPlayer, in detail: MatchDetail) -> Double? {
        guard detail.holes > 0,
              let gross = grossToPar(for: player, in: detail) else { return nil }
        let played = holesPlayed(for: player, in: detail)
        let handicap = player.handicap ?? 0
        let raw = Double(gross) - handicap * Double(played) / Double(detail.holes)
        return (raw * 10).rounded() / 10
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

    /// "-0.6" / "+1.2" / "E" / "—" — one decimal, signed.
    static func netLabel(_ net: Double?) -> String {
        guard let net else { return "—" }
        if abs(net) < 0.05 { return "E" }
        return String(format: "%+.1f", net)
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
