//
//  TournamentDetailViewModel.swift
//  Sticks
//
//  Slice 55: state for the tournament detail — GET /tournaments/:id
//  (info, rounds, roster, cumulative leaderboard, win odds) with a
//  quiet refetch after pull-to-refresh or a newly bound round.
//

import Foundation
import Observation

@Observable
final class TournamentDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var response: TournamentDetailResponse?

    private let tournamentId: String
    private let api: APIClient

    init(tournamentId: String, api: APIClient = .shared) {
        self.tournamentId = tournamentId
        self.api = api
    }

    /// Fetches the detail. `quiet` keeps the current content on screen
    /// during the refetch (pull-to-refresh, post-create refresh); the
    /// first load shows the full-screen loading state. A 401 signs out.
    func load(session: SessionStore, quiet: Bool = false) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if !quiet, response == nil { phase = .loading }
        do {
            response = try await api.tournamentDetail(id: tournamentId, token: token)
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if response == nil { phase = .failed(error.message) }
        } catch {
            if response == nil {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
