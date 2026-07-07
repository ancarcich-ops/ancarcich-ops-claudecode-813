//
//  UserProfile.swift
//  Sticks
//
//  Shapes for GET /me/profile — the caller's editable profile. Decoded
//  tolerantly (counts default to 0, optionals stay nil) so additive
//  server changes never break clients.
//

import Foundation

/// The caller's profile as returned by GET/POST /me/profile.
nonisolated struct UserProfile: Equatable {
    let username: String
    /// Nil or empty means "no custom name" — fall back to @username.
    let displayName: String?
    let ghin: String?
    let avatarUrl: String?
    /// The player's self-set index goal — nil when unset.
    let targetIndex: Double?
    /// Read-only auto-computed Sticks index — nil until enough rounds.
    let computedIndex: Double?
    let indexFromRounds: Int
    let totalRounds: Int
}

extension UserProfile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case username, displayName, ghin, avatarUrl, targetIndex
        case computedIndex, indexFromRounds, totalRounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        // GHIN may arrive as a string or a number.
        if let string = try? container.decodeIfPresent(String.self, forKey: .ghin) {
            ghin = string
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .ghin) {
            ghin = String(number)
        } else {
            ghin = nil
        }
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        targetIndex = try container.decodeIfPresent(Double.self, forKey: .targetIndex)
        computedIndex = try container.decodeIfPresent(Double.self, forKey: .computedIndex)
        indexFromRounds = try container.decodeIfPresent(Int.self, forKey: .indexFromRounds) ?? 0
        totalRounds = try container.decodeIfPresent(Int.self, forKey: .totalRounds) ?? 0
    }
}

nonisolated struct ProfileResponse: Decodable {
    let profile: UserProfile
}
