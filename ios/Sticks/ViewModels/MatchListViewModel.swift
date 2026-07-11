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

    /// Posted with userInfo ["matchId": String] after a round is created
    /// from a non-Home tab — Home reloads and pushes that match's detail.
    static let sticksOpenMatch = Notification.Name("sticksOpenMatch")

    /// Posted by the welcome flow's "New round" CTA — Home opens the
    /// create wizard as if + New round were tapped.
    static let sticksStartNewRound = Notification.Name("sticksStartNewRound")
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

    /// Monotonic load counter — quick filter switches can race, and a
    /// stale response must never overwrite a newer filter's results.
    private var loadGeneration = 0

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

    /// Fetches matches, scoped server-side by `group` (nil → default
    /// feed, "public" → ungrouped only, a group id → that group's
    /// cross-group set). While a refetch is in flight the previous list
    /// keeps showing — no empty-state flash on filter switches. A 401
    /// signs the user out; other failures only surface as a full-screen
    /// error when there's nothing to show yet.
    func load(session: SessionStore, group: String? = nil) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        if matches.isEmpty { phase = .loading }
        do {
            let response = try await api.matches(group: group, token: token)
            guard generation == loadGeneration else { return }
            matches = response.matches
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            guard generation == loadGeneration else { return }
            if matches.isEmpty { phase = .failed(error.message) }
        } catch {
            guard generation == loadGeneration else { return }
            if matches.isEmpty {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
