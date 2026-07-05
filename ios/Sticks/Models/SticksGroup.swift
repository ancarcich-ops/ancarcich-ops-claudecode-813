//
//  SticksGroup.swift
//  Sticks
//
//  Group shapes returned by GET/POST /groups and /groups/join.
//  Decoded tolerantly — counts default to 0, memberNames to [] — so
//  additive server changes never break older clients.
//

import Foundation

/// One group as it appears in the groups payload.
nonisolated struct SticksGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    /// 6-character invite code.
    let inviteCode: String
    let memberCount: Int
    let matchCount: Int
    /// First 4 member display names, for the avatar stack.
    let memberNames: [String]
    let createdAt: Date?

    /// Monogram initials — up to two letters from the group name.
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

extension SticksGroup: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, slug, inviteCode, memberCount, matchCount
        case memberNames, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        matchCount = try container.decodeIfPresent(Int.self, forKey: .matchCount) ?? 0
        memberNames = try container.decodeIfPresent([String].self, forKey: .memberNames) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

nonisolated struct GroupsResponse: Decodable {
    let groups: [SticksGroup]
}

nonisolated struct GroupResponse: Decodable {
    let group: SticksGroup
}
