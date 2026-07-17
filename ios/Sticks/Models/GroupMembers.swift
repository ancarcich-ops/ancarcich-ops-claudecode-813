//
//  GroupMembers.swift
//  Sticks
//
//  Slice 64: shapes for GET /groups/:id/members — the group roster
//  (owner first, then by join date). Decoded tolerantly: optionals
//  default, and a malformed member row drops out of the list instead
//  of failing the whole response.
//

import Foundation

/// One member in the group roster.
nonisolated struct GroupMemberRow: Identifiable {
    let userId: String
    /// Nil for a rare account-less row — rendered but never tappable.
    let username: String?
    let displayName: String
    /// "owner" | "member".
    let role: String
    let joinedAt: Date?
    let isYou: Bool
    let avatarUrl: String?
    let avatarSeed: String?
    let avatarVariant: String?

    var id: String { userId }
    var isOwner: Bool { role.lowercased() == "owner" }
}

extension GroupMemberRow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case userId, username, displayName, role, joinedAt, isYou
        case avatarUrl, avatarSeed, avatarVariant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? username
            ?? "Player"
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "member"
        joinedAt = (try? container.decodeIfPresent(Date.self, forKey: .joinedAt)) ?? nil
        isYou = try container.decodeIfPresent(Bool.self, forKey: .isYou) ?? false
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        avatarSeed = try container.decodeIfPresent(String.self, forKey: .avatarSeed)
        avatarVariant = try container.decodeIfPresent(String.self, forKey: .avatarVariant)
    }
}

/// The group header echoed back with the roster.
nonisolated struct GroupMembersGroup: Decodable {
    let id: String
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

/// Envelope for GET /groups/:id/members. A member row that fails to
/// decode is dropped (lossy) rather than failing the whole roster.
nonisolated struct GroupMembersResponse: Decodable {
    let group: GroupMembersGroup
    let members: [GroupMemberRow]

    private enum CodingKeys: String, CodingKey { case group, members }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decode(GroupMembersGroup.self, forKey: .group)
        let lossy = try container.decodeIfPresent([LossyMember].self, forKey: .members) ?? []
        members = lossy.compactMap(\.row)
    }

    /// Wrapper that swallows a single bad element during decode.
    private struct LossyMember: Decodable {
        let row: GroupMemberRow?

        init(from decoder: Decoder) throws {
            row = try? GroupMemberRow(from: decoder)
        }
    }
}
