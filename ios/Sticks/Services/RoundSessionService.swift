//
//  RoundSessionService.swift
//  Sticks
//
//  Round-scoped owner of the on-course companions — the lock screen
//  Live Activity, the watch snapshot, and the background location
//  session. The GPS screen is a consumer of this service, not the
//  owner of the companions.
//
//  Lifecycle:
//  - Starts the first time the GPS screen opens on an IN_PROGRESS match.
//  - Persists across screen navigation, app backgrounding, and phone lock.
//  - Ends on FINISH ROUND success, the poll reporting COMPLETED, sign-out,
//    or the GPS screen opening on a different match (one round at a time).
//  - The Live Activity's staleDate backstop covers force-quit and system
//    kills — no update loop survives those, by design.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class RoundSessionService {
    static let shared = RoundSessionService()

    /// Single location source shared by the GPS screen and this session.
    /// Background delivery is enabled only while a round is active.
    let location = LocationService()

    /// Match the active round session belongs to — nil when no round.
    private(set) var activeMatchId: String?

    /// Last hole displayed on the GPS screen (index into the round).
    /// Advanced by score entry, manual rail picks, and — slice 7.2 — GPS
    /// auto-advance when the player walks off a finished hole toward the
    /// next tee (`autoAdvanceIfNeeded`), including from background fixes
    /// while the phone stays locked.
    private(set) var holeIndex = 0

    /// Hole index an auto-advance walked away from WITHOUT a score — the
    /// ENTER SCORE sheet defaults to it the next time it opens.
    private(set) var suggestedScoreIndex: Int?

    @ObservationIgnored private var viewModel: MatchDetailViewModel?
    /// Auth session for watch-initiated score posts — weak because the
    /// app root owns it; cleared with the round.
    @ObservationIgnored private weak var session: SessionStore?
    @ObservationIgnored private var isGPSScreenVisible = false
    /// Bumped to invalidate in-flight observation loops when the session
    /// ends or restarts.
    @ObservationIgnored private var generation = 0

    private init() {}

    var isActive: Bool { activeMatchId != nil }

    // MARK: - GPS screen hooks

    /// The GPS screen appeared: run foreground location for the map even
    /// when no round session starts (completed matches, spectators).
    func gpsScreenAppeared() {
        isGPSScreenVisible = true
        location.start()
    }

    /// The GPS screen left. The round session — and its companions and
    /// background location — persists; location stops only when no round
    /// is active.
    func gpsScreenDisappeared() {
        isGPSScreenVisible = false
        if !isActive { location.stop() }
    }

    // MARK: - Tab visibility (slice 13)

    /// Hidden tabs stay mounted — switching away from HOME with the GPS
    /// screen open on a match with NO active round would keep foreground
    /// location running. Stop it; the round-scoped path is untouched.
    func homeTabHidden() {
        guard !isActive else { return }
        location.stop()
    }

    /// Back on HOME: resume foreground location only when the GPS screen
    /// is still the visible pushed screen (idempotent if a round already
    /// keeps location running).
    func homeTabShown() {
        guard isGPSScreenVisible else { return }
        location.start()
    }

    // MARK: - Round lifecycle

    /// Starts (or re-attaches to) the round session for an IN_PROGRESS
    /// match. Opening a different match's GPS screen ends the previous
    /// round first — exactly one round at a time.
    func beginRound(viewModel: MatchDetailViewModel, holeIndex: Int, session: SessionStore) {
        guard let detail = viewModel.detail, detail.status == .inProgress else { return }
        if activeMatchId == detail.id {
            self.viewModel = viewModel
            self.session = session
            return
        }
        if isActive { endRound() }

        activeMatchId = detail.id
        self.viewModel = viewModel
        self.session = session
        self.holeIndex = holeIndex
        suggestedScoreIndex = nil
        resetAutoAdvance()
        // Streaks must be earned from fixes delivered AFTER the round
        // starts — not the stale fix already sitting in LocationService.
        lastAdvanceFixSequence = location.fixSequence
        // Background delivery ON only for the life of the round.
        location.setBackgroundUpdates(true)
        location.start()
        WatchSessionService.shared.activate()
        startObserving()
    }

    /// Records the hole currently displayed on the GPS screen. Manual
    /// rail picks and score-driven advances reset the auto-advance gates
    /// (manual override wins — evidence must be re-earned on the picked
    /// hole); the echo call after an auto-advance is a no-op.
    func setHole(index: Int, matchId: String) {
        guard activeMatchId == matchId, index != holeIndex else { return }
        holeIndex = index
        resetAutoAdvance()
    }

    /// Returns and clears the unscored hole index an auto-advance walked
    /// away from, so the score sheet defaults to it exactly once.
    func consumeSuggestedScoreIndex(matchId: String) -> Int? {
        guard activeMatchId == matchId, let index = suggestedScoreIndex else { return nil }
        suggestedScoreIndex = nil
        return index
    }

    /// Tears the round session down: ends the Live Activity, clears the
    /// watch, and disables background location the moment the round ends
    /// so the app never tracks outside a round. Called on FINISH ROUND
    /// success, the poll reporting COMPLETED, sign-out, or a match switch.
    func endRound() {
        guard isActive else { return }
        generation += 1
        activeMatchId = nil
        viewModel = nil
        session = nil
        suggestedScoreIndex = nil
        resetAutoAdvance()
        location.setBackgroundUpdates(false)
        if !isGPSScreenVisible { location.stop() }
        RoundActivityService.shared.end()
        WatchSessionService.shared.clear()
    }

    // MARK: - Observation loop

    /// Re-runs `sync()` whenever anything it reads changes: the GPS fix
    /// (LocationService), the displayed hole (`holeIndex`), or match state
    /// from the view model's 30s poll and optimistic score updates.
    private func startObserving() {
        generation += 1
        observe(generation: generation)
    }

    private func observe(generation: Int) {
        guard generation == self.generation, isActive else { return }
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observe(generation: generation)
            }
        }
    }

    /// Pushes the current round state to the Live Activity and the watch.
    /// Ends the session when the poll reports the match COMPLETED. The
    /// downstream services own their own dedupe/throttle (≥5yd TO PIN
    /// delta, 1s throttle, latest-wins watch context).
    private func sync() {
        guard let viewModel,
              let detail = viewModel.detail,
              detail.id == activeMatchId,
              detail.holes > 0 else { return }

        if detail.status == .completed {
            endRound()
            return
        }
        guard detail.status == .inProgress else { return }

        // Slice 7.2: runs on every NEW fix — including background fixes —
        // and may advance holeIndex before the pushes below, so the lock
        // screen and watch flip to the next hole in the same pass.
        autoAdvanceIfNeeded(detail: detail)

        let index = min(holeIndex, detail.holes - 1)
        let hole = detail.holeNumber(at: index)
        let geo = viewModel.response?.holeGeo[hole]

        // Strictly player-anchored distances for the Live Activity — the
        // tee fallback never masquerades as TO PIN on the lock screen.
        let playerCoordinate = playerAnchorCoordinate(geo: geo)
        let playerDistances = playerCoordinate.flatMap { geo?.distances(from: $0) }

        let scores = detail.players.first { $0.id == detail.myMatchPlayerId }?.scoresByHole ?? [:]
        var holesScored = 0
        var myScoredHoles = 0
        var toPar = 0
        // Wearer's per-hole (strokes − par) in round order — the Live
        // Activity's progress strip. All nil for spectators.
        var holeDiffs: [Int?] = []
        holeDiffs.reserveCapacity(detail.holes)
        for holeOffset in 0 ..< detail.holes {
            let holeNumber = detail.holeNumber(at: holeOffset)
            if !detail.players.isEmpty,
               detail.players.allSatisfy({ $0.scoresByHole[holeNumber] != nil }) {
                holesScored += 1
            }
            if let strokes = scores[holeNumber] {
                myScoredHoles += 1
                toPar += strokes - detail.par(at: holeOffset)
                holeDiffs.append(strokes - detail.par(at: holeOffset))
            } else {
                holeDiffs.append(nil)
            }
        }
        let isSeated = detail.myMatchPlayerId != nil

        RoundActivityService.shared.startOrUpdate(
            matchId: detail.id,
            courseName: detail.courseName,
            state: RoundActivityAttributes.ContentState(
                hole: hole,
                par: detail.par(at: index),
                toPinYds: playerDistances.map { Int($0.center.rounded()) },
                frontYds: playerDistances.map { Int($0.front.rounded()) },
                backYds: playerDistances.map { Int($0.back.rounded()) },
                holesScored: holesScored,
                totalHoles: detail.holes,
                myToPar: isSeated && myScoredHoles > 0 ? toPar : nil,
                holeDiffs: holeDiffs,
                holeRoundIndex: index,
                // Constant placeholder so Equatable dedupe works — the real
                // timestamp is stamped by RoundActivityService at push time.
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        )

        // The watch keeps the tee fallback so it stays useful off-course
        // (unlike the Live Activity, which is strictly player-anchored).
        WatchSessionService.shared.send(watchSnapshot(detail: detail))
    }

    // MARK: - Watch snapshot + commands (slice 9)

    /// The active round's detail, or nil when no round is live — the
    /// validity gate for every watch command.
    private func activeDetail() -> MatchDetail? {
        guard isActive,
              let detail = viewModel?.detail,
              detail.id == activeMatchId,
              detail.status == .inProgress,
              detail.holes > 0 else { return nil }
        return detail
    }

    /// Snapshot of the current round state — the payload for both context
    /// pushes and watch command replies.
    func currentWatchSnapshot() -> RoundSnapshot? {
        activeDetail().map { watchSnapshot(detail: $0) }
    }

    private func watchSnapshot(detail: MatchDetail) -> RoundSnapshot {
        let index = min(holeIndex, detail.holes - 1)
        let hole = detail.holeNumber(at: index)
        let geo = viewModel?.response?.holeGeo[hole]
        // Tee fallback keeps the watch useful off-course (unlike the
        // Live Activity, which is strictly player-anchored).
        let anchor = playerAnchorCoordinate(geo: geo) ?? geo?.teeCoordinate
        let distances = anchor.flatMap { geo?.distances(from: $0) }
        let myScores = detail.players.first { $0.id == detail.myMatchPlayerId }?.scoresByHole ?? [:]
        let isSeated = detail.myMatchPlayerId != nil

        var holesScored = 0
        var myScoredHoles = 0
        var toPar = 0
        for holeOffset in 0 ..< detail.holes {
            let holeNumber = detail.holeNumber(at: holeOffset)
            if !detail.players.isEmpty,
               detail.players.allSatisfy({ $0.scoresByHole[holeNumber] != nil }) {
                holesScored += 1
            }
            if let strokes = myScores[holeNumber] {
                myScoredHoles += 1
                toPar += strokes - detail.par(at: holeOffset)
            }
        }

        return RoundSnapshot(
            courseName: detail.courseName,
            hole: hole,
            holeIndex: index,
            par: detail.par(at: index),
            frontYds: distances.map { Int($0.front.rounded()) },
            centerYds: distances.map { Int($0.center.rounded()) },
            backYds: distances.map { Int($0.back.rounded()) },
            holesScored: holesScored,
            totalHoles: detail.holes,
            myToPar: isSeated && myScoredHoles > 0 ? toPar : nil,
            isSeated: isSeated,
            myScore: myScores[hole],
            updatedAt: Date()
        )
    }

    /// Applies a hole switch sent from the watch. `index` is the absolute
    /// round index. Semantics match a manual rail tap — the auto-advance
    /// gates reset inside `setHole`, and the GPS screen (if open) follows
    /// via its holeIndex observation.
    func applyWatchSetHole(index: Int) -> WatchCommandReply {
        guard let detail = activeDetail() else {
            return .failure("Open a round on your iPhone first.")
        }
        guard index >= 0, index < detail.holes else {
            return .failure("That hole isn't in this round.")
        }
        setHole(index: index, matchId: detail.id)
        guard let snapshot = currentWatchSnapshot() else {
            return .failure("Open a round on your iPhone first.")
        }
        return .snapshot(snapshot)
    }

    /// Posts the WEARER's score from the watch through the existing score
    /// path (optimistic local apply + quiet re-fetch), then replies with
    /// the recomputed snapshot. Never posts for anyone else's seat.
    func applyWatchScore(hole: Int, strokes: Int) async -> WatchCommandReply {
        guard let viewModel, let session, let detail = activeDetail() else {
            return .failure("Open a round on your iPhone first.")
        }
        guard let playerId = detail.myMatchPlayerId else {
            return .failure("You don't have a seat in this match.")
        }
        guard (1 ... 30).contains(strokes),
              (0 ..< detail.holes).contains(where: { detail.holeNumber(at: $0) == hole }) else {
            return .failure("That score doesn't look right.")
        }
        do {
            try await viewModel.submitScore(playerId: playerId, hole: hole, strokes: strokes, session: session)
        } catch let error as APIError {
            return .failure(error.message)
        } catch {
            return .failure("Couldn't save the score. Try again.")
        }
        // Auto-advance: confirming the wearer's score on the CURRENT hole
        // moves the round straight to the next hole — the reply snapshot
        // below (and the phone's GPS screen, via its holeIndex observation)
        // lands on the new hole. Scoring an earlier hole stays put.
        let index = min(holeIndex, detail.holes - 1)
        if hole == detail.holeNumber(at: index), index + 1 < detail.holes {
            setHole(index: index + 1, matchId: detail.id)
        }
        guard let snapshot = currentWatchSnapshot() else {
            return .failure("Open a round on your iPhone first.")
        }
        return .snapshot(snapshot)
    }

    // MARK: - GPS auto-advance (slice 7.2)

    /// Within this many yards of the green center counts as "reached the
    /// current hole's green" — gate 1 evidence.
    private static let holeFinishedProximityYards: Double = 40
    /// Consecutive fixes the departure condition must hold (jitter guard).
    private static let departureStreakRequired = 3

    /// True once the player has been within 40yd of the CURRENT hole's
    /// green center while it was current. Resets on any hole change —
    /// manual picks therefore suppress auto-advance until evidence is
    /// re-earned on the picked hole.
    @ObservationIgnored private var reachedCurrentGreen = false
    /// Consecutive fixes where the player is closer to the next hole's
    /// tee than to the current hole's green.
    @ObservationIgnored private var departureStreak = 0
    /// Fix sequence last fed into the gates — sync() also re-runs on
    /// poll/hole changes, and streaks must count FIXES, not re-runs.
    @ObservationIgnored private var lastAdvanceFixSequence = 0

    private func resetAutoAdvance() {
        reachedCurrentGreen = false
        departureStreak = 0
    }

    /// Two gates, both required, evaluated per fix:
    /// 1. HOLE-FINISHED EVIDENCE — the player has been within 40yd of the
    ///    current green at any point while the hole was current, OR has a
    ///    score entered on the current hole.
    /// 2. DEPARTURE — closer to the NEXT hole's tee than to the current
    ///    hole's green, held for 3 consecutive fixes.
    /// Forward only, one hole at a time, never past the final hole.
    /// Silently skipped (manual/score advancement only) when the current
    /// green or next tee is unmapped, or the player isn't on the course.
    private func autoAdvanceIfNeeded(detail: MatchDetail) {
        guard location.fixSequence != lastAdvanceFixSequence,
              let fix = location.coordinate,
              location.isAuthorized else { return }
        lastAdvanceFixSequence = location.fixSequence

        let index = min(holeIndex, detail.holes - 1)
        let nextIndex = index + 1
        guard nextIndex < detail.holes else { return }

        let hole = detail.holeNumber(at: index)
        let nextHole = detail.holeNumber(at: nextIndex)
        guard let green = viewModel?.response?.holeGeo[hole]?.greenCoordinate,
              let nextTee = viewModel?.response?.holeGeo[nextHole]?.teeCoordinate else {
            departureStreak = 0
            return
        }

        let toGreen = GolfGeo.yards(from: fix, to: green)

        // Off-course fixes (driving home mid-round) never advance holes.
        guard toGreen <= GolfGeo.onCourseThresholdYards else {
            departureStreak = 0
            return
        }

        if toGreen <= Self.holeFinishedProximityYards {
            reachedCurrentGreen = true
        }
        let myScore = detail.players
            .first { $0.id == detail.myMatchPlayerId }?
            .scoresByHole[hole]
        let hasFinishedEvidence = reachedCurrentGreen || myScore != nil

        if GolfGeo.yards(from: fix, to: nextTee) < toGreen {
            departureStreak += 1
        } else {
            departureStreak = 0
        }

        guard hasFinishedEvidence, departureStreak >= Self.departureStreakRequired else { return }

        // Walking off without scoring is exactly when the score sheet
        // should come back to the hole just left.
        if myScore == nil { suggestedScoreIndex = index }
        holeIndex = nextIndex
        resetAutoAdvance()
    }

    /// Player coordinate when GPS is authorized, has a fix, and the player
    /// is within ~2 miles of the hole — mirrors the GPS screen's anchor
    /// rule so the lock screen never shows tee distances as TO PIN.
    private func playerAnchorCoordinate(geo: HoleGeo?) -> CLLocationCoordinate2D? {
        guard let coordinate = location.coordinate,
              location.isAuthorized,
              let reference = geo?.greenCoordinate ?? geo?.teeCoordinate,
              GolfGeo.yards(from: coordinate, to: reference) <= GolfGeo.onCourseThresholdYards
        else { return nil }
        return coordinate
    }
}
