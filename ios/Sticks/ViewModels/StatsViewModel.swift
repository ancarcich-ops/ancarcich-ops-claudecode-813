//
//  StatsViewModel.swift
//  Sticks
//
//  Loads GET /stats. A 404 means no stats yet (empty state); refreshes
//  keep the previous stats on transient failures.
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
