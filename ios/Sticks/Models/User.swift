//
//  User.swift
//  Sticks
//

import Foundation

/// Authenticated Sticks user as returned by /auth/login and /me.
nonisolated struct User: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    let displayName: String
}
