//
//  MatchDetailViewModel.swift
//  Sticks
//
//  Loads GET /matches/:id and keeps it fresh with a 30s foreground poll.
//

import Foundation
import Observation

@Observable
final class MatchDetailViewModel {
    enum Phase: Equatable {
        /// First load with nothing cached yet.
        case loading
        /// Detail loaded.
        case loaded
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var response: MatchDetailResponse?

    private let api: APIClient
    private let matchId: String

    init(matchId: String, api: APIClient = .shared) {
        self.matchId = matchId
        self.api = api
    }

    var detail: MatchDetail? { response?.match }

    /// Players with the caller's row first, then by seat order.
    var sortedPlayers: [MatchDetailPlayer] {
        guard let detail = response?.match else { return [] }
        return detail.players.sorted { a, b in
            let aIsMine = a.id == detail.myMatchPlayerId
            let bIsMine = b.id == detail.myMatchPlayerId
            if aIsMine != bIsMine { return aIsMine }
            return (a.seat ?? Int.max) < (b.seat ?? Int.max)
        }
    }

    /// Fetches the match detail. A 401 signs the user out. When `quiet`,
    /// failures never disturb already-displayed data (used by the poll).
    func load(session: SessionStore, quiet: Bool = false) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if response == nil && !quiet { phase = .loading }
        do {
            response = try await api.matchDetail(id: matchId, token: token)
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if response == nil && !quiet { phase = .failed(error.message) }
        } catch {
            if response == nil && !quiet {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
