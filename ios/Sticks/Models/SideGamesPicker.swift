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
    /// The game's stored settings as served, or nil. Keys come from the
    /// game's `settings` schema — never guessed (an invented key is
    /// dropped silently, which is how a setting "doesn't stick").
    let config: [String: SideGameConfigValue]?
    /// The fields this game takes, served — render controls from this.
    let settings: [SideGameSetting]
    /// False when a game needs more than a flat form (Match's per-player
    /// strokes, Team vs team's rules) — show "set this up on the web".
    let settingsComplete: Bool

    var id: String { kind }

    private enum CodingKeys: String, CodingKey {
        case kind, label, blurb, on, eligible, ineligibleReason, locked, config, settings, settingsComplete
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
        config = try? container.decodeIfPresent([String: SideGameConfigValue].self, forKey: .config)
        settings = (try? container.decodeIfPresent([SideGameSetting].self, forKey: .settings)) ?? []
        settingsComplete = (try? container.decode(Bool.self, forKey: .settingsComplete)) ?? true
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

/// A JSON scalar in a game's stored config or a setting's default —
/// choice values are strings, targets and stakes are numbers, toggles
/// are booleans. Encodable so a draft can be posted back verbatim.
nonisolated enum SideGameConfigValue: Decodable, Encodable, Hashable {
    case text(String)
    case number(Double)
    case flag(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text((try? container.decode(String.self)) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .flag(let value): try container.encode(value)
        }
    }

    var stringValue: String? { if case .text(let value) = self { return value }; return nil }
    var numberValue: Double? { if case .number(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .flag(let value) = self { return value }; return nil }
}

/// One settings field a game takes, served by the GET — the app renders
/// controls from this and never from a guessed field name. Types are
/// `choice`, `boolean`, `number` and `money`; a field may `dependOn` a
/// boolean sibling that has to be on for it to mean anything.
nonisolated struct SideGameSetting: Decodable, Identifiable, Hashable {
    let key: String
    let label: String
    let type: String
    let defaultValue: SideGameConfigValue?
    let choices: [SideGameSettingChoice]?
    let dependsOn: String?
    /// One line of help under the label ("Empty or 0 means no money.").
    let blurb: String?
    /// Bounds for number/money fields — steppers and clamps use these
    /// rather than invented limits.
    let min: Double?
    let max: Double?
    let step: Double?

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, label, type, choices, dependsOn, blurb, min, max, step
        case defaultValue = "default"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? container.decode(String.self, forKey: .key)) ?? ""
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        type = (try? container.decode(String.self, forKey: .type)) ?? "choice"
        defaultValue = try? container.decodeIfPresent(SideGameConfigValue.self, forKey: .defaultValue)
        choices = try? container.decodeIfPresent([SideGameSettingChoice].self, forKey: .choices)
        dependsOn = try? container.decodeIfPresent(String.self, forKey: .dependsOn)
        blurb = try? container.decodeIfPresent(String.self, forKey: .blurb)
        min = try? container.decodeIfPresent(Double.self, forKey: .min)
        max = try? container.decodeIfPresent(Double.self, forKey: .max)
        step = try? container.decodeIfPresent(Double.self, forKey: .step)
    }
}

/// One option of a `choice` setting.
nonisolated struct SideGameSettingChoice: Decodable, Hashable {
    let value: SideGameConfigValue
    let label: String
    let blurb: String?
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
