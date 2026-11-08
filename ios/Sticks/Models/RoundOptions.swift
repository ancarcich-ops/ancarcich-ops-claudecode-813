//
//  RoundOptions.swift
//  Sticks
//
//  Slice 92: GET /round-options — the labels, blurbs and rules the
//  new-round form is built from. The server owns this copy so the app
//  and the website describe a round the same way (the stored enum —
//  INDIVIDUAL/SCRAMBLE/BOTH — stays a wire value; it's never shown).
//  All fields decode tolerantly; a bundled fallback mirrors the live
//  payload so the form is never blank when the fetch fails.
//

import Foundation

nonisolated struct RoundOptionsResponse {
    var playerCounts: [RoundPlayerCount]
    var roundFormats: [RoundFormatOption]
    var scoringModes: [RoundScoringMode]
    var teamHandicapModes: [TeamHandicapMode]
    var teamRules: [TeamRuleChoice]
    var maxPlayers: Int

    /// The chosen count's blurb ("Solo round — no opponents, no odds.").
    func playerCount(_ count: Int) -> RoundPlayerCount? {
        playerCounts.first { $0.count == count }
    }

    func format(id: String) -> RoundFormatOption? {
        roundFormats.first { $0.id == id }
    }

    func scoringMode(id: String) -> RoundScoringMode? {
        scoringModes.first { $0.id == id }
    }

    func teamHandicapMode(id: String) -> TeamHandicapMode? {
        teamHandicapModes.first { $0.id == id }
    }

    func teamRule(id: String) -> TeamRuleChoice? {
        teamRules.first { $0.id == id }
    }
}

nonisolated struct RoundPlayerCount: Decodable, Hashable, Identifiable {
    let count: Int
    let label: String
    let blurb: String

    var id: Int { count }
}

/// One round format. `minPlayers` gates which formats are offered for
/// the chosen player count (a twosome is never offered a team format —
/// hidden, not disabled). `usesTeams` turns on the team-handicap and
/// team-rules questions.
nonisolated struct RoundFormatOption: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let blurb: String
    let minPlayers: Int
    let usesTeams: Bool
}

nonisolated struct RoundScoringMode: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    /// The two-word gist under the label ("Handicap", "Straight up",
    /// "Group strokes").
    let hint: String?
    let blurb: String
}

nonisolated struct TeamHandicapMode: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let hint: String?
    let blurb: String
}

/// One team-vs-team scoring rule. Every published rule compares two
/// balls per side — `needsTwoBalls` — which is why a SCRAMBLE (one ball
/// per team) can never run one, and the form prunes them there. Rules
/// are multi-select: each picked rule runs simultaneously with its own
/// leaderboard. `hasOptions` marks VEGAS, which carries extra settings
/// (birdie flip, doubling holes, stake) — unselectable until its panel
/// ships.
nonisolated struct TeamRuleChoice: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let blurb: String
    let needsTwoBalls: Bool
    let hasOptions: Bool
}

extension RoundOptionsResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case playerCounts, roundFormats, scoringModes, teamHandicapModes, teamRules
        case soloSkipsSideGames, maxPlayers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func list<T: Decodable>(_ key: CodingKeys, as type: T.Type) -> [T] {
            ((try? container.decode([Lenient<T>].self, forKey: key)) ?? []).compactMap(\.value)
        }

        playerCounts = list(CodingKeys.playerCounts, as: RoundPlayerCount.self)
        roundFormats = list(CodingKeys.roundFormats, as: RoundFormatOption.self)
        scoringModes = list(CodingKeys.scoringModes, as: RoundScoringMode.self)
        teamHandicapModes = list(CodingKeys.teamHandicapModes, as: TeamHandicapMode.self)
        teamRules = list(CodingKeys.teamRules, as: TeamRuleChoice.self)
        maxPlayers = (try? container.decodeIfPresent(Int.self, forKey: .maxPlayers)) ?? 8
    }

    /// Wrapper so one malformed row never sinks the array.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) {
            value = try? T(from: decoder)
        }
    }
}

extension RoundOptionsResponse {
    /// Offline fallback mirroring the live payload — identical copy the
    /// website serves, used until (or instead of) a successful fetch so
    /// the Round step always has words on screen.
    static let fallback = RoundOptionsResponse(
        playerCounts: [
            RoundPlayerCount(
                count: 1,
                label: "Solo",
                blurb: "Solo round — no opponents, no odds. Just log your card."
            ),
            RoundPlayerCount(count: 2, label: "Twosome", blurb: "Add up to 8 on the next step."),
            RoundPlayerCount(count: 3, label: "Threesome", blurb: "Add up to 8 on the next step."),
            RoundPlayerCount(
                count: 4,
                label: "Foursome+",
                blurb: "Add up to 8 on the next step. Unlocks Teams (one ball per side) and Individual + Team scoring."
            ),
        ],
        roundFormats: [
            RoundFormatOption(
                id: "INDIVIDUAL",
                label: "Individual",
                blurb: "Every player keeps their own score; live odds price each player to win the match.",
                minPlayers: 1,
                usesTeams: false
            ),
            RoundFormatOption(
                id: "SCRAMBLE",
                label: "Teams",
                blurb: "Players split into 2 teams; live odds price team-vs-team.",
                minPlayers: 4,
                usesTeams: true
            ),
            RoundFormatOption(
                id: "BOTH",
                label: "Individual and Team",
                blurb: "Each player keeps their own score AND teams are scored from those individual scores. Live odds still price players individually; a team-vs-team side game tracks the team competition.",
                minPlayers: 4,
                usesTeams: true
            ),
        ],
        scoringModes: [
            RoundScoringMode(
                id: "NET",
                label: "Net",
                hint: "Handicap",
                blurb: "Lowest gross minus handicap wins. Lower handicap is the market favorite at open."
            ),
            RoundScoringMode(
                id: "GROSS",
                label: "Gross",
                hint: "Straight up",
                blurb: "Lowest raw score wins. Handicaps are shown but do not affect the result."
            ),
            RoundScoringMode(
                id: "CUSTOM",
                label: "Custom",
                hint: "Group strokes",
                blurb: "The group sets the strokes given, rather than deriving them from handicaps."
            ),
        ],
        teamHandicapModes: [
            TeamHandicapMode(
                id: "GROSS",
                label: "Gross",
                hint: "No allowance",
                blurb: "Pure team score with no handicap adjustment — most casual scrambles."
            ),
            TeamHandicapMode(
                id: "AVG",
                label: "Avg",
                hint: "Mean of HCPs",
                blurb: "Each side plays off the average of its players' handicaps."
            ),
            TeamHandicapMode(
                id: "CUSTOM",
                label: "Custom",
                hint: "Group decides",
                blurb: "The group sets each side's allowance by hand."
            ),
        ],
        teamRules: [
            TeamRuleChoice(
                id: "BEST_BALL",
                label: "Best Ball",
                blurb: "Each team's score on a hole = its lowest player's score",
                needsTwoBalls: true,
                hasOptions: false
            ),
            TeamRuleChoice(
                id: "WORST_BALL",
                label: "Worst Ball",
                blurb: "Each team's score on a hole = its highest player's score",
                needsTwoBalls: true,
                hasOptions: false
            ),
            TeamRuleChoice(
                id: "HIGH_LOW",
                label: "Low Ball, Low Total",
                blurb: "2 points per hole: 1 for the lowest individual, 1 for the lowest team sum; ties push",
                needsTwoBalls: true,
                hasOptions: false
            ),
            TeamRuleChoice(
                id: "HIGH_LOW_BALL",
                label: "Low Ball / High Ball",
                blurb: "Compare the two low scores (\u{201C}low ball\u{201D}) and the two high scores (\u{201C}high ball\u{201D}) against each other. The lowest of each group wins.",
                needsTwoBalls: true,
                hasOptions: false
            ),
            TeamRuleChoice(
                id: "SUM",
                label: "Sum of Strokes",
                blurb: "Each team's score = sum of all teammates' gross strokes",
                needsTwoBalls: true,
                hasOptions: false
            ),
            TeamRuleChoice(
                id: "AGGREGATE_NET",
                label: "Aggregate Net",
                blurb: "Each team's score = sum of all teammates' net strokes",
                needsTwoBalls: true,
                hasOptions: false
            ),
            TeamRuleChoice(
                id: "VEGAS",
                label: "Vegas",
                blurb: "Each team's two scores form a 2-digit number (low first); lower team wins the difference in points.",
                needsTwoBalls: true,
                hasOptions: true
            ),
        ],
        maxPlayers: 8
    )
}
