//
//  SideGamesPicker.swift
//  Sticks
//
//  Slice 99: shapes for the server-driven side-games editor and the
//  round-scoring editor (slice 100), probed live against /api/mobile:
//  - GET  /matches/:id/side-games → { editable, reason, games: [...] } —
//    the server owns the game list and eligibility, so a rule change
//    reaches the app without a build and the app can never offer a game
//    the scorer will refuse.
//  - POST /matches/:id/side-games → { ok, kinds } — full replacement;
//    reconcile against `kinds` (the server drops ineligible games).
//  - POST /matches/:id/scoring → { ok, scoringMode, groupId, handicaps }
//    — scoring mode / posted group / per-player handicaps mid-round.
//

import Foundation

/// One game row in the GET side-games picker.
nonisolated struct SideGameOption: Decodable, Identifiable, Hashable {
    let kind: String
    let label: String
    let blurb: String
    let on: Bool
    /// False = render disabled with `ineligibleReason` (never hidden).
    let eligible: Bool
    let ineligibleReason: String?
    /// Only ever Team vs team with teams assigned — the toggle is
    /// disabled and the game stays on; unchecking it appears to work
    /// and then comes back after the round trip.
    let locked: Bool
    /// The game's stored settings, or nil.
    let config: SideGameConfigValue?

    var id: String { kind }

    private enum CodingKeys: String, CodingKey {
        case kind, label, blurb, on, eligible, ineligibleReason, locked, config
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        label = (try? container.decode(String.self, forKey: .label)) ?? kind
        blurb = (try? container.decode(String.self, forKey: .blurb)) ?? ""
        on = (try? container.decode(Bool.self, forKey: .on)) ?? false
        eligible = (try? container.decode(Bool.self, forKey: .eligible)) ?? true
        ineligibleReason = try? container.decodeIfPresent(String.self, forKey: .ineligibleReason)
        locked = (try? container.decode(Bool.self, forKey: .locked)) ?? false
        config = try? container.decodeIfPresent(SideGameConfigValue.self, forKey: .config)
    }
}

/// The GET side-games payload. `editable: false` means read-only —
/// show `reason` ("Only the round's creator can change side games.",
/// "This round is final.").
nonisolated struct SideGamesPicker: Decodable {
    let editable: Bool
    let reason: String?
    let games: [SideGameOption]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        editable = (try? container.decode(Bool.self, forKey: .editable)) ?? false
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        games = (try? container.decode([SideGameOption].self, forKey: .games)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case editable, reason, games
    }
}

/// A game's stored settings — decoded leniently; only fields the app
/// actually renders are typed. (The server currently strips Skins'
/// `carryOver` — the field is here so it lights up when the server
/// round-trips it.)
nonisolated struct SideGameConfigValue: Decodable, Hashable {
    let carryOver: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        carryOver = try? container.decodeIfPresent(Bool.self, forKey: .carryOver)
    }

    private enum CodingKeys: String, CodingKey {
        case carryOver
    }
}

/// Body for POST /matches/:id/scoring — every field optional, send only
/// what changed (synthesized encoding drops nil keys). Handicaps go by
/// `matchPlayerId`, never position — a stale roster order must not hand
/// one player another's index. A blank/absent handicap row means
/// "unchanged", not scratch.
nonisolated struct ScoringUpdate: Encodable {
    struct Handicap: Encodable {
        let matchPlayerId: String
        let handicap: String
    }

    var scoringMode: String?
    var groupId: String?
    var handicaps: [Handicap]?
}

/// POST /matches/:id/scoring response — the state afterwards. The
/// server silently drops an unrecognised scoringMode and falls an
/// unknown group back to public, so reconcile against this rather than
/// assuming the request stuck.
nonisolated struct ScoringResponse: Decodable {
    let ok: Bool
    let scoringMode: String?
    let groupId: String?
    let handicaps: [ScoringHandicap]?

    nonisolated struct ScoringHandicap: Decodable {
        let matchPlayerId: String
        let handicap: Double?
    }
}
