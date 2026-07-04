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

    /// Players in seat order — the cycle order for score entry.
    var seatOrderedPlayers: [MatchDetailPlayer] {
        (response?.match.players ?? []).sorted { a, b in
            let aSeat = a.seat ?? Int.max
            let bSeat = b.seat ?? Int.max
            if aSeat != bSeat { return aSeat < bSeat }
            return a.id < b.id
        }
    }

    /// Next seat-ordered player (wrapping) still missing a score on `hole`,
    /// starting after `playerId`. Nil when the hole is complete.
    func nextUnscoredPlayer(onHole hole: Int, after playerId: String) -> MatchDetailPlayer? {
        let players = seatOrderedPlayers
        guard !players.isEmpty else { return nil }
        let start = players.firstIndex { $0.id == playerId } ?? -1
        for offset in 1 ... players.count {
            let candidate = players[(start + offset + players.count) % players.count]
            if candidate.id != playerId && candidate.scoresByHole[hole] == nil {
                return candidate
            }
        }
        return nil
    }

    /// POSTs a score (nil clears the hole). On success the local scorecard
    /// is updated immediately and a quiet re-fetch is kicked off — no
    /// waiting for the 30s poll. Throws APIError for the sheet to display.
    func submitScore(playerId: String, hole: Int, strokes: Int?, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.postScore(
                matchId: matchId,
                matchPlayerId: playerId,
                hole: hole,
                strokes: strokes,
                token: token
            )
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        applyScoreLocally(playerId: playerId, hole: hole, strokes: strokes)
        Task { await load(session: session, quiet: true) }
    }

    /// Optimistic local update after a confirmed POST /score.
    private func applyScoreLocally(playerId: String, hole: Int, strokes: Int?) {
        guard var updated = response,
              let index = updated.match.players.firstIndex(where: { $0.id == playerId }) else { return }
        if let strokes {
            updated.match.players[index].scoresByHole[hole] = strokes
        } else {
            updated.match.players[index].scoresByHole.removeValue(forKey: hole)
        }
        response = updated
    }

    /// True when every seated player has a score on every hole of the
    /// round — the condition for showing the FINISH ROUND button.
    var isRoundComplete: Bool {
        guard let detail = response?.match, !detail.players.isEmpty else { return false }
        for index in 0 ..< detail.holes {
            let hole = detail.holeNumber(at: index)
            for player in detail.players where player.scoresByHole[hole] == nil {
                return false
            }
        }
        return true
    }

    /// POSTs the round completion (idempotent server-side), then re-fetches
    /// the match so the COMPLETED state renders immediately — no waiting
    /// for the 30s poll. Throws APIError for the UI to display.
    func completeMatch(session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.postComplete(matchId: matchId, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await load(session: session, quiet: true)
    }

    /// POSTs a FIX TEE crowdfix. Returns the server verdict — `ok: false`
    /// carries a `reason` the UI shows verbatim. On success a quiet re-fetch
    /// picks up the corrected tee geometry. Throws APIError on transport or
    /// HTTP errors; a 401 signs the user out.
    func submitTee(hole: Int, lat: Double, lng: Double, accuracyYd: Int, session: SessionStore) async throws -> TeeResponse {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            let verdict = try await api.postTee(
                matchId: matchId,
                hole: hole,
                lat: lat,
                lng: lng,
                accuracyYd: accuracyYd,
                token: token
            )
            if verdict.ok {
                Task { await load(session: session, quiet: true) }
            }
            return verdict
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
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
