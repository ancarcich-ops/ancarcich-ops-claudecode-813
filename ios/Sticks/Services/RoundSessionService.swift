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

    /// Last hole viewed on the GPS screen (index into the round). Score
    /// entry advances it via the GPS screen; there is deliberately no
    /// GPS-based auto-hole detection — if the user walks to the next hole
    /// without unlocking, the banner keeps the last hole's green and the
    /// yardage keeps updating.
    private(set) var holeIndex = 0

    @ObservationIgnored private var viewModel: MatchDetailViewModel?
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

    // MARK: - Round lifecycle

    /// Starts (or re-attaches to) the round session for an IN_PROGRESS
    /// match. Opening a different match's GPS screen ends the previous
    /// round first — exactly one round at a time.
    func beginRound(viewModel: MatchDetailViewModel, holeIndex: Int) {
        guard let detail = viewModel.detail, detail.status == .inProgress else { return }
        if activeMatchId == detail.id {
            self.viewModel = viewModel
            return
        }
        if isActive { endRound() }

        activeMatchId = detail.id
        self.viewModel = viewModel
        self.holeIndex = holeIndex
        // Background delivery ON only for the life of the round.
        location.setBackgroundUpdates(true)
        location.start()
        WatchSessionService.shared.activate()
        startObserving()
    }

    /// Records the hole currently displayed on the GPS screen.
    func setHole(index: Int, matchId: String) {
        guard activeMatchId == matchId else { return }
        holeIndex = index
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
        for holeOffset in 0 ..< detail.holes {
            let holeNumber = detail.holeNumber(at: holeOffset)
            if !detail.players.isEmpty,
               detail.players.allSatisfy({ $0.scoresByHole[holeNumber] != nil }) {
                holesScored += 1
            }
            if let strokes = scores[holeNumber] {
                myScoredHoles += 1
                toPar += strokes - detail.par(at: holeOffset)
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
                // Constant placeholder so Equatable dedupe works — the real
                // timestamp is stamped by RoundActivityService at push time.
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        )

        // The watch keeps the tee fallback so it stays useful off-course
        // (unlike the Live Activity, which is strictly player-anchored).
        let watchAnchor = playerCoordinate ?? geo?.teeCoordinate
        let watchDistances = watchAnchor.flatMap { geo?.distances(from: $0) }
        WatchSessionService.shared.send(RoundSnapshot(
            courseName: detail.courseName,
            hole: hole,
            par: detail.par(at: index),
            frontYds: watchDistances.map { Int($0.front.rounded()) },
            centerYds: watchDistances.map { Int($0.center.rounded()) },
            backYds: watchDistances.map { Int($0.back.rounded()) },
            holesScored: holesScored,
            totalHoles: detail.holes,
            myToPar: isSeated && myScoredHoles > 0 ? toPar : nil,
            updatedAt: Date()
        ))
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
