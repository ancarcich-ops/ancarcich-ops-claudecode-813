//
//  StatsViewModel.swift
//  Sticks
//
//  Loads GET /stats. A 404 means no stats yet (empty state); refreshes
//  keep the previous stats on transient failures. Also posts the index
//  goal (POST /me/target-index), deletes rounds (DELETE /matches/:id),
//  and removes the caller's own scores from rounds they didn't create
//  (DELETE /matches/:id/my-scores) — reloading stats after each so
//  every derived number stays honest.
//

import Foundation
import Observation

@Observable
final class StatsViewModel {
    enum Phase: Equatable {
        /// First load with nothing to show yet.
        case loading
        /// Stats loaded.
        case loaded
        /// 404 — nothing logged yet.
        case empty
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var stats: PlayerStats?
    private(set) var baselines: [StatsBaseline] = []

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// POSTs the index goal (nil clears it) and reloads stats.
    /// Returns a user-facing error message, or nil on success.
    func setTargetIndex(_ value: Double?, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        do {
            _ = try await api.setTargetIndex(value, token: token)
            await load(session: session)
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// DELETEs a round and reloads stats. Returns a user-facing error
    /// message (the server's own text on 403), or nil on success.
    func deleteRound(matchId: String, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        do {
            try await api.deleteMatch(id: matchId, token: token)
            await load(session: session)
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// DELETEs only the caller's scores from a round and reloads stats.
    /// Returns a user-facing error message (the server's own text on
    /// 403), or nil on success.
    func removeMyScores(matchId: String, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        do {
            try await api.removeMyScores(matchId: matchId, token: token)
            await load(session: session)
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "Can't reach Sticks. Check your connection and try again."
        }
    }

    func load(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if stats == nil { phase = .loading }
        do {
            let response = try await api.stats(token: token)
            stats = response.stats
            baselines = response.baselines
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError where error.statusCode == 404 {
            stats = nil
            baselines = []
            phase = .empty
        } catch let error as APIError {
            if stats == nil { phase = .failed(error.message) }
        } catch {
            if stats == nil {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
