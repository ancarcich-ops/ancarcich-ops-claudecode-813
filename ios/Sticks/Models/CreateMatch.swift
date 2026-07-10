//
//  CreateMatch.swift
//  Sticks
//
//  Slice 20: shapes for the create-match flow — course search
//  (GET /courses), player suggestions (GET /players/suggest), and the
//  POST /matches body/response. All decoded tolerantly so additive
//  server changes never break older clients.
//

import Foundation

// MARK: - Courses

/// One row of GET /courses (?q= search or ?lat=&lng= nearby).
nonisolated struct CourseResult: Identifiable, Hashable {
    let id: String
    let name: String
    let city: String?
    let holes: Int
    let access: String?
    /// Present only on nearby (?lat&lng) results.
    let distanceMi: Double?
}

extension CourseResult: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, city, holes, access, distanceMi
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        holes = try container.decodeIfPresent(Int.self, forKey: .holes) ?? 18
        access = try container.decodeIfPresent(String.self, forKey: .access)
        distanceMi = try container.decodeIfPresent(Double.self, forKey: .distanceMi)
    }
}

nonisolated struct CoursesResponse: Decodable {
    let courses: [CourseResult]
}

// MARK: - Tees

/// One tee set from GET /courses/tees?name=. Identified by name+gender
/// ("Blue · M" and "Blue · W" are distinct rows with their own ratings).
nonisolated struct CourseTee: Identifiable, Hashable {
    let name: String
    let gender: String
    let rating: Double
    let slope: Int
    let yardage: Int?
    /// True when the rating/slope are estimated, not officially rated.
    let estimated: Bool

    var id: String { "\(name)|\(gender)" }
}

extension CourseTee: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, gender, rating, slope, yardage, estimated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        gender = try container.decodeIfPresent(String.self, forKey: .gender) ?? "M"
        rating = try container.decode(Double.self, forKey: .rating)
        slope = try container.decode(Int.self, forKey: .slope)
        yardage = try container.decodeIfPresent(Int.self, forKey: .yardage)
        estimated = try container.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
    }
}

nonisolated struct CourseTeesResponse: Decodable {
    let tees: [CourseTee]
    let defaultTeeName: String?

    private enum CodingKeys: String, CodingKey {
        case tees, defaultTeeName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tees = try container.decodeIfPresent([CourseTee].self, forKey: .tees) ?? []
        defaultTeeName = try container.decodeIfPresent(String.self, forKey: .defaultTeeName)
    }
}

// MARK: - Player suggestions

/// One row of GET /players/suggest — a recent partner (no query, carries
/// lastHandicap) or a search hit (?q=, lastHandicap null).
nonisolated struct PlayerSuggestion: Identifiable, Hashable {
    let userId: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let lastHandicap: Double?

    var id: String { userId }
}

extension PlayerSuggestion: Decodable {
    private enum CodingKeys: String, CodingKey {
        case userId, username, displayName, avatarUrl, lastHandicap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        let name = try container.decodeIfPresent(String.self, forKey: .displayName)
        displayName = name?.isEmpty == false ? name! : username
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        lastHandicap = try container.decodeIfPresent(Double.self, forKey: .lastHandicap)
    }
}

nonisolated struct PlayerSuggestResponse: Decodable {
    let players: [PlayerSuggestion]
    /// The caller's own most recent handicap — present only on the
    /// no-query (recent partners) call.
    let myLastHandicap: Double?

    private enum CodingKeys: String, CodingKey {
        case players, myLastHandicap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        players = try container.decodeIfPresent([PlayerSuggestion].self, forKey: .players) ?? []
        myLastHandicap = try container.decodeIfPresent(Double.self, forKey: .myLastHandicap)
    }
}

// MARK: - POST /matches

/// One seat in the POST /matches body. `userId` present = a linked
/// Sticks account; absent = a guest seat. `teeName`/`teeGender` lock the
/// round's differential to the tee played — omitted when the course has
/// no rated tees (the server falls back to the course default).
/// Synthesized encoding drops nil keys (encodeIfPresent), which is
/// exactly what the server expects. `team` (0 or 1) is sent only for
/// SCRAMBLE/BOTH rounds — omitted for INDIVIDUAL.
nonisolated struct CreateMatchPlayer: Encodable {
    let displayName: String
    let handicap: Double
    let userId: String?
    let teeName: String?
    let teeGender: String?
    let team: Int?
}

/// Body for POST /matches. `scheduledAt` is intentionally omitted —
/// the server defaults it to now. Optional keys (sideGames, groupId)
/// are dropped when nil. `format` is INDIVIDUAL / SCRAMBLE / BOTH —
/// BOTH makes the server spin up the team match itself (never send
/// TEAM_VS_TEAM as a side game).
nonisolated struct CreateMatchRequest: Encodable {
    let courseName: String
    let holes: Int
    let startingHole: Int
    let scoringMode: String
    let format: String
    let players: [CreateMatchPlayer]
    let sideGames: [String]?
    let groupId: String?
}

nonisolated struct CreatedMatch: Decodable {
    let id: String
}

nonisolated struct CreateMatchResponse: Decodable {
    let match: CreatedMatch
}
