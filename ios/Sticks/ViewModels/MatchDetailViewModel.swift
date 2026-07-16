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
        /// First load failed with a user-facing message. The status code
        /// distinguishes access denials (403/404 — retrying can't help)
        /// from transient transport failures (retry makes sense).
        case failed(message: String, statusCode: Int)
    }

    private(set) var phase: Phase = .loading
    private(set) var response: MatchDetailResponse?
    /// The caller's live share links for this round (slice 29).
    private(set) var shares: [RoundShare] = []
    /// Slice 61: the seat currently being claimed — nil when idle.
    /// Drives the claim card's spinner/disabled state.
    private(set) var claimingSeatId: String?
    /// Slice 61: last claim failure — the server message, shown verbatim
    /// inline on the claim card. Cleared on the next attempt/success.
    private(set) var claimError: String?

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

    /// POSTs the reopen (creator-only), then re-fetches the match so the
    /// reverted state (IN_PROGRESS, or UPCOMING if scoreless) renders
    /// immediately. Throws APIError — a 403's server message is shown
    /// verbatim; a 401 signs the user out.
    func reopenMatch(session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.postReopen(matchId: matchId, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await load(session: session, quiet: true)
    }

    /// DELETEs the round (creator-only). The caller pops back to the
    /// feed and refreshes it on success. Throws APIError — a 403's
    /// server message is shown verbatim; a 401 signs the user out.
    func deleteMatch(session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.deleteMatch(id: matchId, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
    }

    /// POSTs the full pars array (creator-only, any status), then
    /// re-fetches so the scorecard re-renders with the new pars.
    /// Throws APIError — 400/403 server messages are shown verbatim.
    func setPars(_ pars: [Int], session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            _ = try await api.setPars(matchId: matchId, pars: pars, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await load(session: session, quiet: true)
    }

    /// POSTs the full desired set of side-game kinds (creator-only),
    /// then re-fetches so the standings/side-game sections update.
    func setSideGames(kinds: [String], session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            _ = try await api.setSideGames(matchId: matchId, kinds: kinds, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await load(session: session, quiet: true)
    }

    /// POSTs one game's settings (Targets stat/target/ante, Wolf
    /// rotation/push rule), then quiet-refetches so the leaderboards
    /// recompute against the new config. Throws APIError — 403
    /// (non-creator) shows the server message verbatim; 401 signs out.
    func setSideGameConfig<C: Encodable>(kind: String, config: C, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.setSideGameConfig(matchId: matchId, kind: kind, config: config, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await load(session: session, quiet: true)
    }

    /// POSTs one side-game event (Snake 3-putt, BBB award, Match press),
    /// applies it optimistically to the local events, then quiet-refetches
    /// so the game's leaderboard recomputes server-side. Throws APIError —
    /// 400s (game not enabled, round final) show verbatim; 401 signs out.
    func recordSideGameEvent(gameKind: String, kind: String, hole: Int, matchPlayerId: String?, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.recordSideGameEvent(
                matchId: matchId,
                kind: kind,
                hole: hole,
                matchPlayerId: matchPlayerId,
                token: token
            )
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        applyEventLocally(gameKind: gameKind, kind: kind, hole: hole, matchPlayerId: matchPlayerId)
        Task { await load(session: session, quiet: true) }
    }

    /// The three mutually-exclusive Wolf picks per hole.
    private static let wolfPickKinds: Set<String> = ["PARTNER", "LONE_WOLF", "PRE_LONE_WOLF"]

    /// Optimistic local mirror of the server's event semantics after a
    /// confirmed POST: BBB awards are single-holder (replace on assign,
    /// clear on nil player); Wolf picks are mutually exclusive per hole
    /// (replace on new pick, toggle off on repeat); THREE_PUTT, PRESS
    /// and PUSH toggle.
    private func applyEventLocally(gameKind: String, kind: String, hole: Int, matchPlayerId: String?) {
        guard var updated = response else { return }
        var events = updated.sideGameEvents
        switch kind {
        case "BINGO", "BANGO", "BONGO":
            events.removeAll { $0.kind == kind && $0.hole == hole }
            if let matchPlayerId {
                events.append(SideGameEvent(gameKind: gameKind, hole: hole, kind: kind, matchPlayerId: matchPlayerId))
            }
        case _ where Self.wolfPickKinds.contains(kind):
            let existing = events.first { Self.wolfPickKinds.contains($0.kind) && $0.hole == hole }
            events.removeAll { Self.wolfPickKinds.contains($0.kind) && $0.hole == hole }
            if existing?.kind != kind || existing?.matchPlayerId != matchPlayerId {
                events.append(SideGameEvent(gameKind: gameKind, hole: hole, kind: kind, matchPlayerId: matchPlayerId))
            }
        default:
            let matches: (SideGameEvent) -> Bool = {
                $0.kind == kind && $0.hole == hole && $0.matchPlayerId == matchPlayerId
            }
            if events.contains(where: matches) {
                events.removeAll(where: matches)
            } else {
                events.append(SideGameEvent(gameKind: gameKind, hole: hole, kind: kind, matchPlayerId: matchPlayerId))
            }
        }
        updated.sideGameEvents = events
        response = updated
    }

    /// Slice 61: POSTs the claim linking an unlinked seat to the caller,
    /// then re-fetches the detail so canClaimSeat / myMatchPlayerId /
    /// canScore all update — the card disappears and "your round"
    /// treatment turns on. Errors land in `claimError` (server messages
    /// verbatim); a 401 signs the user out.
    func claimSeat(matchPlayerId: String, session: SessionStore) async {
        guard claimingSeatId == nil else { return }
        guard let token = session.token else {
            session.signOut()
            return
        }
        claimingSeatId = matchPlayerId
        claimError = nil
        defer { claimingSeatId = nil }
        do {
            try await api.claimSeat(matchId: matchId, matchPlayerId: matchPlayerId, token: token)
            await load(session: session, quiet: true)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            claimError = error.message
        } catch {
            claimError = "Couldn't claim that seat. Check your connection and try again."
        }
    }

    /// Fetches the caller's live share links. Quiet on failure — an
    /// unreachable list keeps whatever was already displayed.
    func loadShares(session: SessionStore) async {
        guard let token = session.token else { return }
        do {
            shares = try await api.listShares(matchId: matchId, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch {
            // Keep the previous list — the card's actions surface errors.
        }
    }

    /// Creates a live share link, then refreshes the list so the new
    /// row (with its public URL) appears immediately.
    func createShare(includeScores: Bool, destAddress: String?, bufferMin: Int, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            _ = try await api.createShare(
                matchId: matchId,
                includeScores: includeScores,
                destAddress: destAddress,
                bufferMin: bufferMin,
                token: token
            )
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await loadShares(session: session)
    }

    /// Stops (revokes) a share link, then refreshes the list.
    func deleteShare(id: String, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            try await api.deleteShare(shareId: id, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
        await loadShares(session: session)
    }

    /// POSTs a crowd call (nil withdraws the current one). The response's
    /// myCall / wagerCounts / totalCalls — and re-blended probabilities,
    /// when the server returns them — apply to the local odds immediately,
    /// then a quiet re-fetch pulls the fully re-blended market (chart,
    /// weights) so the odds shift live instead of waiting for the 30s
    /// poll. Throws APIError — a 400 (market closed) shows the server
    /// message verbatim; a 401 signs the user out.
    func placeCall(pickedPlayerId: String?, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            let result = try await api.placeCall(
                matchId: matchId,
                pickedPlayerId: pickedPlayerId,
                token: token
            )
            if var updated = response, var odds = updated.odds {
                odds.myCall = result.myCall
                odds.wagerCounts = result.wagerCounts
                odds.totalCalls = result.totalCalls
                if let probabilities = result.probabilities, !probabilities.isEmpty {
                    odds.probabilities = probabilities
                }
                updated.odds = odds
                response = updated
            }
            Task { await load(session: session, quiet: true) }
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
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
            if response == nil && !quiet {
                phase = .failed(message: error.message, statusCode: error.statusCode)
            }
        } catch {
            if response == nil && !quiet {
                phase = .failed(
                    message: "Can't reach Sticks. Check your connection and try again.",
                    statusCode: -1
                )
            }
        }
    }
}
