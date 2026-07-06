//
//  GroupLeaderboard.swift
//  Sticks
//
//  Shapes for GET /groups/:id/leaderboard. Decoded tolerantly — counts
//  default to 0, flags to false, arrays to [] — so additive server
//  changes never break older clients.
//

import Foundation

/// One member's row on the group leaderboard.
nonisolated struct LeaderboardRow: Identifiable, Hashable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let avatarSeed: String?
    let avatarVariant: String?
    let matchesPlayed: Int
    let mainWins: Int
    let stablefordWins: Int
    let skinsWins: Int
    let nassauWins: Int
    let bbbWins: Int
    let snakeWins: Int
    let wolfWins: Int
    let totalWins: Int

    var id: String { userId }

    /// Preferred display name — falls back to the username.
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username
    }
}

extension LeaderboardRow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case userId, username, displayName, avatarUrl, avatarSeed, avatarVariant
        case matchesPlayed, mainWins, stablefordWins, skinsWins, nassauWins
        case bbbWins, snakeWins, wolfWins, totalWins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        avatarSeed = try container.decodeIfPresent(String.self, forKey: .avatarSeed)
        avatarVariant = try container.decodeIfPresent(String.self, forKey: .avatarVariant)
        matchesPlayed = try container.decodeIfPresent(Int.self, forKey: .matchesPlayed) ?? 0
        mainWins = try container.decodeIfPresent(Int.self, forKey: .mainWins) ?? 0
        stablefordWins = try container.decodeIfPresent(Int.self, forKey: .stablefordWins) ?? 0
        skinsWins = try container.decodeIfPresent(Int.self, forKey: .skinsWins) ?? 0
        nassauWins = try container.decodeIfPresent(Int.self, forKey: .nassauWins) ?? 0
        bbbWins = try container.decodeIfPresent(Int.self, forKey: .bbbWins) ?? 0
        snakeWins = try container.decodeIfPresent(Int.self, forKey: .snakeWins) ?? 0
        wolfWins = try container.decodeIfPresent(Int.self, forKey: .wolfWins) ?? 0
        totalWins = try container.decodeIfPresent(Int.self, forKey: .totalWins) ?? 0
    }
}

/// A course record line — best gross/net round on a course.
nonisolated struct CourseRecord: Identifiable, Hashable {
    let courseName: String
    let bestDisplayName: String
    /// Holder's user id when the server provides one — drives the
    /// identity-color dot next to the holder name.
    let userId: String?
    let gross: Int?
    let net: Double?
    let scheduledAt: Date?

    var id: String { courseName + "·" + bestDisplayName }
}

extension CourseRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case courseName, bestDisplayName, userId, bestUserId, gross, net, scheduledAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        bestDisplayName = try container.decodeIfPresent(String.self, forKey: .bestDisplayName) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
            ?? container.decodeIfPresent(String.self, forKey: .bestUserId)
        gross = try container.decodeIfPresent(Int.self, forKey: .gross)
        net = try container.decodeIfPresent(Double.self, forKey: .net)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
    }
}

/// Head-to-head main-game results between Sticks-linked members.
/// `wins[A][B]` = times A beat B in a main-game result they both played.
nonisolated struct HeadToHead: Hashable {
    nonisolated struct Member: Identifiable, Hashable {
        let userId: String
        let displayName: String
        let username: String

        var id: String { userId }

        /// Preferred display name — falls back to the username.
        var name: String { displayName.isEmpty ? username : displayName }
    }

    let users: [Member]
    let wins: [String: [String: Int]]

    static let empty = HeadToHead(users: [], wins: [:])

    /// Times `userId` beat `opponentId`.
    func wins(of userId: String, over opponentId: String) -> Int {
        wins[userId]?[opponentId] ?? 0
    }
}

extension HeadToHead.Member: Decodable {
    private enum CodingKeys: String, CodingKey {
        case userId, displayName, username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
    }
}

extension HeadToHead: Decodable {
    private enum CodingKeys: String, CodingKey {
        case users, wins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([Member].self, forKey: .users) ?? []
        wins = try container.decodeIfPresent([String: [String: Int]].self, forKey: .wins) ?? [:]
    }
}

/// A reigning champion entry (per side-game kind).
nonisolated struct ChampionEntry: Identifiable, Hashable {
    nonisolated struct Winner: Decodable, Hashable {
        let displayName: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case displayName }
    }

    let kind: String
    let label: String
    let winners: [Winner]
    let courseName: String
    let scheduledAt: Date?

    var id: String { kind + "·" + label }
}

extension ChampionEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, label, winners, courseName, scheduledAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        winners = try container.decodeIfPresent([Winner].self, forKey: .winners) ?? []
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName) ?? ""
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
    }
}

/// A member's main-game win streak.
nonisolated struct StreakEntry: Identifiable, Hashable {
    let displayName: String
    let currentMainStreak: Int
    let bestMainStreak: Int

    var id: String { displayName }
}

extension StreakEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case displayName, currentMainStreak, bestMainStreak
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        currentMainStreak = try container.decodeIfPresent(Int.self, forKey: .currentMainStreak) ?? 0
        bestMainStreak = try container.decodeIfPresent(Int.self, forKey: .bestMainStreak) ?? 0
    }
}

/// The full leaderboard payload for one group.
nonisolated struct GroupLeaderboard {
    let rows: [LeaderboardRow]
    let completedMatches: Int
    let hasMain: Bool
    let hasStableford: Bool
    let hasSkins: Bool
    let hasNassau: Bool
    let hasBbb: Bool
    let hasSnake: Bool
    let hasWolf: Bool
    let courseRecords: [CourseRecord]
    let champions: [ChampionEntry]
    let streaks: [StreakEntry]
    let headToHead: HeadToHead

    /// Rows sorted by totalWins desc, ties: matchesPlayed asc, then name.
    var sortedRows: [LeaderboardRow] {
        rows.sorted { a, b in
            if a.totalWins != b.totalWins { return a.totalWins > b.totalWins }
            if a.matchesPlayed != b.matchesPlayed { return a.matchesPlayed < b.matchesPlayed }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

extension GroupLeaderboard: Decodable {
    private enum CodingKeys: String, CodingKey {
        case rows, completedMatches
        case hasMain, hasStableford, hasSkins, hasNassau, hasBbb, hasSnake, hasWolf
        case courseRecords, champions, streaks, headToHead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decodeIfPresent([LeaderboardRow].self, forKey: .rows) ?? []
        completedMatches = try container.decodeIfPresent(Int.self, forKey: .completedMatches) ?? 0
        hasMain = try container.decodeIfPresent(Bool.self, forKey: .hasMain) ?? false
        hasStableford = try container.decodeIfPresent(Bool.self, forKey: .hasStableford) ?? false
        hasSkins = try container.decodeIfPresent(Bool.self, forKey: .hasSkins) ?? false
        hasNassau = try container.decodeIfPresent(Bool.self, forKey: .hasNassau) ?? false
        hasBbb = try container.decodeIfPresent(Bool.self, forKey: .hasBbb) ?? false
        hasSnake = try container.decodeIfPresent(Bool.self, forKey: .hasSnake) ?? false
        hasWolf = try container.decodeIfPresent(Bool.self, forKey: .hasWolf) ?? false
        courseRecords = try container.decodeIfPresent([CourseRecord].self, forKey: .courseRecords) ?? []
        champions = try container.decodeIfPresent([ChampionEntry].self, forKey: .champions) ?? []
        streaks = try container.decodeIfPresent([StreakEntry].self, forKey: .streaks) ?? []
        headToHead = try container.decodeIfPresent(HeadToHead.self, forKey: .headToHead) ?? .empty
    }
}

nonisolated struct GroupLeaderboardResponse: Decodable {
    let leaderboard: GroupLeaderboard
}
