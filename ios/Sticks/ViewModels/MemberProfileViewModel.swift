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

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(username: String, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if stats == nil { phase = .loading }
        do {
            let response = try await api.userStats(username: username, token: token)
            stats = response.stats
            baselines = response.baselines
            isSelf = response.isSelf
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
}
