//
//  MatchListViewModel.swift
//  Sticks
//
//  Loads GET /matches and groups results into Live / Upcoming / Recent.
//

import Foundation
import Observation

extension Notification.Name {
    /// Posted after a round is edited, deleted, or marked final on the
    /// detail screen so the home feed refreshes without waiting for a
    /// manual pull.
    static let sticksMatchesDidChange = Notification.Name("sticksMatchesDidChange")
}

@Observable
final class MatchListViewModel {
    enum Phase: Equatable {
        /// First load with nothing cached yet.
        case loading
        /// Matches loaded (possibly empty).
        case loaded
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var matches: [MatchSummary] = []

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var liveMatches: [MatchSummary] {
        matches.filter { $0.status == .inProgress }
    }

    /// Soonest tee time first.
    var upcomingMatches: [MatchSummary] {
        matches.filter { $0.status == .upcoming }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// Most recent round first (server order).
    var recentMatches: [MatchSummary] {
        matches.filter { $0.status == .completed }
    }

    /// Fetches matches. A 401 signs the user out; other failures only
    /// surface as a full-screen error when there's nothing to show yet.
    func load(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if matches.isEmpty { phase = .loading }
        do {
            let response = try await api.matches(token: token)
            matches = response.matches
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if matches.isEmpty { phase = .failed(error.message) }
        } catch {
            if matches.isEmpty {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
