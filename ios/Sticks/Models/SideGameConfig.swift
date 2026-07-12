//
//  SideGameConfig.swift
//  Sticks
//
//  Slice 53: typed configs for the config-driven side games, parsed
//  from the raw JSON strings in MatchDetailResponse.sideGameConfigs
//  and posted back via POST /matches/:id/side-game-config. Decoding
//  is lenient — malformed configs fall back to sensible defaults.
//

import Foundation

/// Targets settings — which stat to chase and how many holes to hit it.
nonisolated struct TargetsConfig: Codable, Hashable {
    var stat: String
    var target: Int
    var ante: Int

    static let parOrBetter = "PAR_OR_BETTER"
    static let birdieOrBetter = "BIRDIE_OR_BETTER"

    private enum CodingKeys: String, CodingKey {
        case stat, target, ante
    }

    init(stat: String, target: Int, ante: Int) {
        self.stat = stat
        self.target = target
        self.ante = ante
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stat = (try? container.decode(String.self, forKey: .stat)) ?? Self.parOrBetter
        target = (try? container.decode(Int.self, forKey: .target)) ?? 9
        ante = (try? container.decode(Int.self, forKey: .ante)) ?? 0
    }

    /// Parses the raw JSON string from sideGameConfigs — nil when the
    /// game has no config saved yet.
    static func decode(from raw: String?) -> TargetsConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TargetsConfig.self, from: data)
    }
}

/// Wolf settings — the order players take being the wolf, plus how
/// pushed holes carry.
nonisolated struct WolfConfig: Codable, Hashable {
    /// matchPlayerIds in wolf order — hole i's wolf is rotation[i % count].
    var rotation: [String]
    var pushRule: String

    static let carry = "CARRY"
    static let noCarry = "NO_CARRY"

    private enum CodingKeys: String, CodingKey {
        case rotation, pushRule
    }

    init(rotation: [String], pushRule: String) {
        self.rotation = rotation
        self.pushRule = pushRule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rotation = (try? container.decode([String].self, forKey: .rotation)) ?? []
        pushRule = (try? container.decode(String.self, forKey: .pushRule)) ?? Self.carry
    }

    /// Parses the raw JSON string from sideGameConfigs — nil when the
    /// game has no config saved yet.
    static func decode(from raw: String?) -> WolfConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WolfConfig.self, from: data)
    }
}
