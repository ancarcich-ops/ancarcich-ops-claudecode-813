//
//  SideGameConfig.swift
//  Sticks
//
//  Slice 53: typed configs for the config-driven side games, parsed
//  from the raw JSON strings in MatchDetailResponse.sideGameConfigs
//  and posted back via POST /matches/:id/side-game-config. Decoding
//  is lenient — malformed configs fall back to sensible defaults.
//
//  Slice 57: Stableford scale, BBB points and Snake stake join the
//  typed configs, backing the new native settings editors.
//
//  Slice 58: Nassau auto-press + stake joins the typed configs.
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

/// Stableford points per result vs par. A config with no `points`
/// table means the standard WHS scale.
nonisolated struct StablefordPoints: Codable, Hashable {
    var albatross: Int
    var eagle: Int
    var birdie: Int
    var par: Int
    var bogey: Int
    var double: Int

    static let whs = StablefordPoints(albatross: 5, eagle: 4, birdie: 3, par: 2, bogey: 1, double: 0)
    static let modified = StablefordPoints(albatross: 8, eagle: 5, birdie: 2, par: 0, bogey: -1, double: -3)

    private enum CodingKeys: String, CodingKey {
        case albatross, eagle, birdie, par, bogey, double
    }

    init(albatross: Int, eagle: Int, birdie: Int, par: Int, bogey: Int, double: Int) {
        self.albatross = albatross
        self.eagle = eagle
        self.birdie = birdie
        self.par = par
        self.bogey = bogey
        self.double = double
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        albatross = (try? container.decode(Int.self, forKey: .albatross)) ?? Self.whs.albatross
        eagle = (try? container.decode(Int.self, forKey: .eagle)) ?? Self.whs.eagle
        birdie = (try? container.decode(Int.self, forKey: .birdie)) ?? Self.whs.birdie
        par = (try? container.decode(Int.self, forKey: .par)) ?? Self.whs.par
        bogey = (try? container.decode(Int.self, forKey: .bogey)) ?? Self.whs.bogey
        double = (try? container.decode(Int.self, forKey: .double)) ?? Self.whs.double
    }
}

/// Stableford settings — nil `points` = standard WHS scale. Saving
/// Standard posts an empty object `{}` (the optional is omitted).
nonisolated struct StablefordConfig: Codable, Hashable {
    var points: StablefordPoints?

    private enum CodingKeys: String, CodingKey {
        case points
    }

    init(points: StablefordPoints?) {
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try? container.decodeIfPresent(StablefordPoints.self, forKey: .points)
    }

    /// Parses the raw JSON string from sideGameConfigs — nil when the
    /// game has no config saved yet.
    static func decode(from raw: String?) -> StablefordConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StablefordConfig.self, from: data)
    }
}

/// Bingo Bango Bongo award weights — non-negative, default 1 each.
nonisolated struct BbbPoints: Codable, Hashable {
    var bingo: Int
    var bango: Int
    var bongo: Int

    static let deflt = BbbPoints(bingo: 1, bango: 1, bongo: 1)

    private enum CodingKeys: String, CodingKey {
        case bingo, bango, bongo
    }

    init(bingo: Int, bango: Int, bongo: Int) {
        self.bingo = bingo
        self.bango = bango
        self.bongo = bongo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bingo = (try? container.decode(Int.self, forKey: .bingo)) ?? 1
        bango = (try? container.decode(Int.self, forKey: .bango)) ?? 1
        bongo = (try? container.decode(Int.self, forKey: .bongo)) ?? 1
    }
}

/// BBB settings — nil `points` = 1/1/1 default.
nonisolated struct BbbConfig: Codable, Hashable {
    var points: BbbPoints?

    private enum CodingKeys: String, CodingKey {
        case points
    }

    init(points: BbbPoints?) {
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try? container.decodeIfPresent(BbbPoints.self, forKey: .points)
    }

    /// Parses the raw JSON string from sideGameConfigs — nil when the
    /// game has no config saved yet.
    static func decode(from raw: String?) -> BbbConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BbbConfig.self, from: data)
    }
}

/// Snake settings — stake nil/0 means no money on the snake;
/// `doubling` (omitted when off) doubles the pot each pass.
nonisolated struct SnakeConfig: Codable, Hashable {
    var stake: Double?
    var doubling: Bool?

    private enum CodingKeys: String, CodingKey {
        case stake, doubling
    }

    init(stake: Double?, doubling: Bool?) {
        self.stake = stake
        self.doubling = doubling
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stake = try? container.decodeIfPresent(Double.self, forKey: .stake)
        doubling = try? container.decodeIfPresent(Bool.self, forKey: .doubling)
    }

    /// Parses the raw JSON string from sideGameConfigs — nil when the
    /// game has no config saved yet.
    static func decode(from raw: String?) -> SnakeConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SnakeConfig.self, from: data)
    }
}

/// Nassau settings — auto-press spawns a new press bet whenever a
/// side falls `autoPressThreshold` holes down inside the front or
/// back match; `stake` is dollars per bet (front, back, total, and
/// each press are each a bet). Presses apply to 2-player rounds only.
nonisolated struct NassauConfig: Codable, Hashable {
    var autoPress: Bool?
    var autoPressThreshold: Int?
    var stake: Double?

    private enum CodingKeys: String, CodingKey {
        case autoPress, autoPressThreshold, stake
    }

    init(autoPress: Bool? = nil, autoPressThreshold: Int? = nil, stake: Double? = nil) {
        self.autoPress = autoPress
        self.autoPressThreshold = autoPressThreshold
        self.stake = stake
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPress = try? container.decodeIfPresent(Bool.self, forKey: .autoPress)
        autoPressThreshold = try? container.decodeIfPresent(Int.self, forKey: .autoPressThreshold)
        stake = try? container.decodeIfPresent(Double.self, forKey: .stake)
    }

    /// Parses the raw JSON string from sideGameConfigs — nil when the
    /// game has no config saved yet.
    static func decode(from raw: String?) -> NassauConfig? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NassauConfig.self, from: data)
    }
}

/// Slice 57: which side-game settings editor sheet is open.
enum SideGameConfigKind: String, Identifiable {
    case stableford = "STABLEFORD"
    case bbb = "BBB"
    case snake = "SNAKE"
    case nassau = "NASSAU"

    var id: String { rawValue }
}
