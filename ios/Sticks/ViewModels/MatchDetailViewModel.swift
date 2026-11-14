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

    /// Slice 93: "targetKey:emoji" pairs with an in-flight reaction —
    /// a second tap on the same chip waits instead of double-firing.
    private var pendingReactions: Set<String> = []

    /// Slice 101: the post-round recap. `.none` is the 404 case — a
    /// round with nothing scored has NO recap entry point at all.
    enum RecapState {
        case idle
        case none
        case loaded(RoundRecap)
        case failed(String)
    }

    private(set) var recapState: RecapState = .idle

    /// Whether the recap tab exists — a finished round with a recap.
    var hasRecap: Bool {
        if case .loaded = recapState { return true }
        return false
    }

    /// The loaded recap payload, when there is one.
    var recapPayload: RoundRecap? {
        if case .loaded(let recap) = recapState { return recap }
        return nil
    }

    private let api: APIClient
    private let matchId: String
    /// The format string the round was opened with. Tournament rounds are
    /// pushed with the tournament's format id (e.g. "scramble-2") on the
    /// navigation stub; the match payload itself only ever carries the
    /// legacy INDIVIDUAL/SCRAMBLE/BOTH values, so this hint is the only
    /// way to recover shared-card context. Nil/legacy → no resolution.
    private let formatHint: String?
    /// Slice 89b: the owning tournament's id (from the navigation stub)
    /// — lets a shared-card round fetch the event's formed sides, since
    /// the match payload carries no tournament reference and leaves
    /// players[].team null.
    private let tournamentId: String?

    init(
        matchId: String,
        formatHint: String? = nil,
        tournamentId: String? = nil,
        api: APIClient = .shared
    ) {
        self.matchId = matchId
        self.formatHint = formatHint
        self.tournamentId = tournamentId
        self.api = api
    }

    /// The legacy format values the server round-trips on every match
    /// payload — anything else is a tournament format id.
    private static let legacyFormats: Set<String> = ["INDIVIDUAL", "SCRAMBLE", "BOTH"]

    /// Slice 89: the resolved tournament format when this round belongs
    /// to a format-aware tournament — nil for standalone rounds (and
    /// when the registry lookup fails, falling back to per-player UI).
    private(set) var tournamentFormat: TournamentFormat?

    /// Scramble-style entry: each side records ONE score per hole on a
    /// single card, never one per player.
    var isSharedCard: Bool { tournamentFormat?.isSharedCard == true }

    /// Slice 89b: the owning tournament's formed sides, fetched when the
    /// format resolves to shared-card entry. Nil when the lookup hasn't
    /// run, failed, or the round is standalone.
    private(set) var tournamentTeams: [TournamentSide]?

    /// One side's shared card: the member whose match row carries the
    /// team's scores, the side's display label, and the member rows.
    struct SideCard: Identifiable, Hashable {
        let label: String
        let cardPlayer: MatchDetailPlayer
        let members: [MatchDetailPlayer]
        var id: String { cardPlayer.id }
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

    /// Slice 89/89b: the round's shared cards, one per side. Sides are
    /// seated from the server's players[].team stamp when present,
    /// otherwise by matching userIds against the tournament's formed
    /// teams. Everything that can't be seated falls into one trailing
    /// bucket, so no player's score is ever dropped. With no formed
    /// teams (or a failed lookup) the whole round is one side — the
    /// original single-card behavior.
    var sideCards: [SideCard] {
        guard isSharedCard else { return [] }
        let players = seatOrderedPlayers
        guard !players.isEmpty else { return [] }

        var teamByUser: [String: Int] = [:]
        if let teams = tournamentTeams {
            for side in teams {
                for member in side.members {
                    if let userId = member.userId {
                        teamByUser[userId] = side.team
                    }
                }
            }
        }

        var byTeam: [Int: [MatchDetailPlayer]] = [:]
        var unseated: [MatchDetailPlayer] = []
        for player in players {
            if let stamp = player.team, let team = Int(stamp) {
                byTeam[team, default: []].append(player)
            } else if let userId = player.userId, let team = teamByUser[userId] {
                byTeam[team, default: []].append(player)
            } else {
                unseated.append(player)
            }
        }

        var cards: [SideCard] = []
        for team in byTeam.keys.sorted() {
            let members = byTeam[team] ?? []
            cards.append(
                SideCard(label: "TEAM \(team)", cardPlayer: cardWinner(members), members: members)
            )
        }
        if !unseated.isEmpty {
            // The sole side keeps the friendly generic label; beside
            // formed teams, unseatable players get their own bucket so
            // their scores stay out of a team's card.
            let label = cards.isEmpty ? "TEAM CARD" : "UNSEEDED"
            cards.append(SideCard(label: label, cardPlayer: cardWinner(unseated), members: unseated))
        }
        return cards
    }

    /// The member whose match row should carry a side's card — the one
    /// with the most holes already scored (so an existing card keeps
    /// collecting); ties break by seat order, then id.
    private func cardWinner(_ players: [MatchDetailPlayer]) -> MatchDetailPlayer {
        players.max { a, b in
            let aHoles = a.scoresByHole.count
            let bHoles = b.scoresByHole.count
            if aHoles != bHoles { return aHoles < bHoles }
            let aSeat = a.seat ?? Int.max
            let bSeat = b.seat ?? Int.max
            if aSeat != bSeat { return aSeat > bSeat }
            return a.id > b.id
        } ?? players[0]
    }

    /// Scorecard rows: the caller's row first normally; on shared-card
    /// entry, one row per side's card.
    var scorecardPlayers: [MatchDetailPlayer] {
        if isSharedCard, !sideCards.isEmpty { return sideCards.map(\.cardPlayer) }
        return sortedPlayers
    }

    /// Side labels aligned with `scorecardPlayers` — non-nil only on
    /// shared-card entry (ScorecardGrid swaps names for these).
    var scorecardSideLabels: [String]? {
        guard isSharedCard, !sideCards.isEmpty else { return nil }
        return sideCards.map(\.label)
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
    /// round — the condition for showing the FINISH ROUND button. On a
    /// shared-card side it's the team's single card that must be full.
    var isRoundComplete: Bool {
        guard let detail = response?.match, !detail.players.isEmpty else { return false }
        if isSharedCard {
            // Every side's card must be full.
            let cards = sideCards.map(\.cardPlayer)
            guard !cards.isEmpty else { return false }
            for index in 0 ..< detail.holes {
                let hole = detail.holeNumber(at: index)
                if cards.contains(where: { $0.scoresByHole[hole] == nil }) {
                    return false
                }
            }
            return true
        }
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

    /// GETs the side-games picker state (slice 99) — which games exist,
    /// their blurbs, what's on, eligibility. The server owns the list so
    /// the app never offers a game the scorer will refuse. Throws
    /// APIError; 401 signs out.
    func sideGamesPicker(session: SessionStore) async throws -> SideGamesPicker {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            return try await api.sideGamesPicker(matchId: matchId, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
    }

    /// Fetches the post-round recap (slice 101). A 404 means nothing is
    /// scored yet — recap state becomes .none and the UI shows NO entry
    /// point at all. A 403 (can't see the round) reads as none too; the
    /// round itself is already failing visibly in that case.
    func loadRecap(session: SessionStore) async {
        guard let token = session.token else { return }
        do {
            recapState = .loaded(try await api.recap(matchId: matchId, token: token))
        } catch let error as APIError where error.statusCode == 404 || error.statusCode == 403 {
            recapState = .none
        } catch let error as APIError {
            // A finished round normally has a recap; a failure here gets
            // a retry affordance, not a silent hole.
            recapState = .failed(error.message)
        } catch {
            recapState = .failed("Can't reach Sticks. Check your connection and try again.")
        }
    }

    /// POSTs round-scoring changes (slice 100) — scoring mode, posted
    /// group, per-player handicaps — then quiet-refetches so every
    /// leaderboard re-derives from the strokes already logged. Returns
    /// the afterwards-state to reconcile against (the server drops an
    /// unrecognised mode and falls an unknown group back to public).
    /// Throws APIError; 403 (non-creator) and 400 (round final) show
    /// verbatim; 401 signs out.
    func setRoundScoring(_ body: ScoringUpdate, session: SessionStore) async throws -> ScoringResponse {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            let response = try await api.setRoundScoring(matchId: matchId, body: body, token: token)
            await load(session: session, quiet: true)
            return response
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
    }

    /// POSTs the full desired set of side-game kinds and returns the
    /// reconciled set actually on afterwards (slice 99) — the server
    /// drops games the round can't play. The detail quiet-refetches
    /// behind the caller's dismiss.
    func setSideGamesReturning(kinds: [String], session: SessionStore) async throws -> [String] {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            let finalKinds = try await api.setSideGames(matchId: matchId, kinds: kinds, token: token)
            await load(session: session, quiet: true)
            return finalKinds
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            throw error
        }
    }

    /// POSTs one game's settings (Targets stat/target/ante, Wolf
    /// rotation/push rule), then quiet-refetches so the leaderboards
    /// recompute against the new config. Throws APIError — 403
    /// (non-creator) shows the server message verbatim; 401 signs out.
    /// A non-empty `dropped` means the app posted a field name the
    /// server doesn't know — surfaced as an error, never ignored.
    func setSideGameConfig<C: Encodable>(kind: String, config: C, session: SessionStore) async throws {
        guard let token = session.token else {
            session.signOut()
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }
        do {
            let dropped = try await api.setSideGameConfig(matchId: matchId, kind: kind, config: config, token: token)
            if !dropped.isEmpty {
                throw APIError(
                    message: "Some settings for this game didn't save — update Sticks and try again.",
                    statusCode: 400
                )
            }
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

    // MARK: - Reactions (slice 93)

    /// True while that chip's toggle is in flight.
    func isReactionPending(emoji: String, targetKey: String) -> Bool {
        pendingReactions.contains("\(targetKey):\(emoji)")
    }

    /// Toggles the caller's reaction on the round or a scored hole:
    /// optimistic flip first, then the POST, then reconciliation with
    /// the server's full post-toggle tally. Hole-level targets parse
    /// their matchPlayerId + hole out of the key — the two ride along
    /// together or neither (the server 400s any other mix). A failure
    /// quiet-refetches to restore the truth; a 401 signs out.
    func toggleReaction(emoji: String, targetKey: String, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        let pendingKey = "\(targetKey):\(emoji)"
        guard !pendingReactions.contains(pendingKey) else { return }

        pendingReactions.insert(pendingKey)
        defer { pendingReactions.remove(pendingKey) }

        applyOptimisticTally(emoji: emoji, targetKey: targetKey)

        let holeTarget = ReactionTarget.holePlayerId(forKey: targetKey)
        do {
            let result = try await api.toggleReaction(
                matchId: matchId,
                emoji: emoji,
                matchPlayerId: holeTarget?.matchPlayerId,
                hole: holeTarget?.hole,
                token: token
            )
            if var updated = response {
                updated.match.reactions[targetKey] = result.reactions
                response = updated
            }
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch {
            await load(session: session, quiet: true)
        }
    }

    /// The optimistic flip of one emoji's tally under a target key.
    private func applyOptimisticTally(emoji: String, targetKey: String) {
        guard var updated = response else { return }
        var tallies = updated.match.reactions[targetKey] ?? []
        if let index = tallies.firstIndex(where: { $0.emoji == emoji }) {
            tallies[index] = tallies[index].toggled()
        } else {
            tallies.append(Reaction(emoji: emoji, count: 1, mine: true))
        }
        updated.match.reactions[targetKey] = tallies
        response = updated
    }

    /// Slice 89: resolves a tournament format id from the navigation
    /// hint against GET /formats. Quiet on failure — an unreachable
    /// registry or unknown id just leaves the per-player behavior.
    private func resolveTournamentFormat(token: String) async {
        guard tournamentFormat == nil,
              let hint = formatHint?.uppercased(),
              !Self.legacyFormats.contains(hint)
        else { return }
        do {
            let registry = try await api.formats(token: token)
            tournamentFormat = registry.groups
                .flatMap(\.formats)
                .first { $0.id.lowercased() == hint.lowercased() }
            // Slice 89b: shared-card rounds also pull the event's formed
            // sides — the match payload leaves players[].team null, so
            // this is where seating comes from. Failure keeps one card.
            if tournamentFormat?.isSharedCard == true, let tournamentId {
                tournamentTeams = try? await api.tournamentDetail(id: tournamentId, token: token).teams
            }
        } catch {
            // Keep per-player behavior; the server still scores the
            // tournament from the most complete card.
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
            await resolveTournamentFormat(token: token)
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
