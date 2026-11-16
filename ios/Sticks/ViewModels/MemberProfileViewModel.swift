//
//  MemberProfileViewModel.swift
//  Sticks
//
//  Slice 63: loads GET /users/:username/stats — another member's
//  read-only stats (same envelope as /stats plus isSelf). Refreshes
//  keep the previous stats on transient failures; a 404 (no such
//  account) surfaces the server's message verbatim.
//

import Foundation
import Observation

@Observable
final class MemberProfileViewModel {
    enum Phase: Equatable {
        /// First load with nothing to show yet.
        case loading
        /// Profile loaded.
        case loaded
        /// First load failed with a user-facing message (404 included).
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var stats: PlayerStats?
    private(set) var baselines: [StatsBaseline] = []
    /// True when the username resolved to the caller — the view routes
    /// to the editable Stats tab instead of this read-only mirror.
    private(set) var isSelf = false
    /// Slice 68: my follow relationship to this profile — nil on
    /// older servers (the Follow button hides).
    private(set) var followState: String?
    /// Slice 68: the profile's userId — the follow-action target.
    private(set) var targetUserId: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(username: String, expectedUserId: String? = nil, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if stats == nil { phase = .loading }
        do {
            let response = try await fetchStats(username: username, userId: expectedUserId, token: token)
            // The server resolved the name to a DIFFERENT account than
            // the link meant (usernames differing only by case). Showing
            // that account's empty stats under this player's name is
            // wrong data; say so instead.
            if let expectedUserId, let resolved = response.targetUserId, resolved != expectedUserId {
                phase = .failed("This player's profile can't be opened right now — another account has a near-identical username.")
                return
            }
            stats = response.stats
            baselines = response.baselines
            isSelf = response.isSelf
            followState = response.followState
            targetUserId = response.targetUserId
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if stats == nil { phase = .failed(error.message) }
        } catch {
            if stats == nil {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }

    /// Fetches by account id when known (server #667 accepts ids), so a
    /// case-colliding handle can't resolve to the wrong account. A 404 on
    /// the id means the server predates id lookup — retry by username,
    /// where the mismatch guard above still catches a wrong resolution.
    private func fetchStats(username: String, userId: String?, token: String) async throws -> StatsResponse {
        guard let userId, !userId.isEmpty else {
            return try await api.userStats(username: username, token: token)
        }
        do {
            return try await api.userStats(username: userId, token: token)
        } catch let error as APIError where error.statusCode == 404 {
            return try await api.userStats(username: username, token: token)
        }
    }
}
