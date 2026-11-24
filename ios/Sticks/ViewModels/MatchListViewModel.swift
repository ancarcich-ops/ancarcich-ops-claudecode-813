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

    /// Live rounds hidden from the caller — stale (>24h in progress)
    /// rounds where the caller holds no seat and isn't the creator.
    private(set) var hiddenMatchIds: Set<String> = []

    /// Stale live rounds the caller CREATED, not yet alerted this app
    /// session — Home surfaces these as a "needs your attention" alert.
    private(set) var attentionMatches: [MatchSummary] = []

    /// matchId → isCreator, resolved via GET /matches/:id for stale
    /// rounds only. Shared across view-model instances (Home + group
    /// feeds) so each stale round is checked at most once per launch.
    private static var creatorCache: [String: Bool] = [:]

    /// Stale rounds already alerted this app session — the owner is
    /// nudged once per launch, not on every refresh.
    private static var alertedMatchIds: Set<String> = []

    /// Monotonic load counter — quick filter switches can race, and a
    /// stale response must never overwrite a newer filter's results.
    private var loadGeneration = 0

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Live rounds visible to the caller. Rounds stuck IN_PROGRESS for
    /// more than 24 hours are almost certainly abandoned, so they only
    /// show for their own seated players (and creator) — never for
    /// other group members or the public feed.
    var liveMatches: [MatchSummary] {
        matches.filter { $0.status == .inProgress && !hiddenMatchIds.contains($0.id) }
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
            applyStaleVisibility()
            await resolveStaleCreators(token: token, generation: generation)
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

    /// The owner acted on (or dismissed) a stale-round alert — don't
    /// nag again this session.
    func markAttentionHandled(_ matchId: String) {
        Self.alertedMatchIds.insert(matchId)
        refreshAttentionMatches()
    }

    // MARK: - Stale (abandoned) live rounds

    /// Recomputes which live rounds the caller may see. A stale round
    /// defaults to hidden until the creator check proves otherwise —
    /// safe default, since seated players are always exempt.
    private func applyStaleVisibility() {
        hiddenMatchIds = Set(
            matches
                .filter { $0.isStaleLive && !$0.isSeatedPlayer && Self.creatorCache[$0.id] != true }
                .map(\.id)
        )
        refreshAttentionMatches()
    }

    private func refreshAttentionMatches() {
        attentionMatches = matches.filter {
            $0.isStaleLive
                && Self.creatorCache[$0.id] == true
                && !Self.alertedMatchIds.contains($0.id)
        }
    }

    /// GET /matches lacks an isCreator flag, so ownership of stale
    /// rounds is resolved via the detail endpoint — cached per launch,
    /// capped at 5 fetches per load (stale rounds are rare). Failures
    /// stay uncached and retry on the next load.
    private func resolveStaleCreators(token: String, generation: Int) async {
        let unresolved = matches
            .filter { $0.isStaleLive && Self.creatorCache[$0.id] == nil }
            .prefix(5)
        guard !unresolved.isEmpty else { return }
        for match in unresolved {
            guard generation == loadGeneration else { return }
            if let detail = try? await api.matchDetail(id: match.id, token: token) {
                Self.creatorCache[match.id] = detail.match.isCreator
            }
        }
        guard generation == loadGeneration else { return }
        applyStaleVisibility()
    }
}
