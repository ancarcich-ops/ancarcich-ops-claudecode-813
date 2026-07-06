//
//  GroupLeaderboardViewModel.swift
//  Sticks
//
//  Loads GET /groups/:id/leaderboard. 403/404 server messages surface
//  verbatim; refreshes keep the previous board on transient failures.
//

import Foundation
import Observation

@Observable
final class GroupLeaderboardViewModel {
    enum Phase: Equatable {
        /// First load with nothing to show yet — skeleton rows.
        case loading
        /// Leaderboard loaded.
        case loaded
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var leaderboard: GroupLeaderboard?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(groupId: String, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if leaderboard == nil { phase = .loading }
        do {
            let response = try await api.groupLeaderboard(groupId: groupId, token: token)
            leaderboard = response.leaderboard
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if leaderboard == nil { phase = .failed(error.message) }
        } catch {
            if leaderboard == nil {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
