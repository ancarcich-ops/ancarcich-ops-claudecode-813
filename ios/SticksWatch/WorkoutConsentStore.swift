//
//  WorkoutConsentStore.swift
//  SticksWatch
//
//  Decides WHETHER the golf workout runs for a round. The workout is a
//  real HealthKit recording (heart rate, energy, ring credit) as well as
//  the thing that keeps Sticks frontmost on the wrist, so it must be the
//  wearer's call — not something that silently begins the moment a round
//  starts.
//
//  Three modes, persisted on the watch:
//    .ask    — default. Prompt once per round, before anything starts.
//    .always — start it automatically, no prompt.
//    .never  — never start it (Sticks still shows yardages; it just
//              won't hold the wrist as long and nothing goes to Health).
//

import Foundation
import Observation

/// What the watch should do when a round goes live.
nonisolated enum WorkoutConsent: String, CaseIterable, Identifiable {
    case ask
    case always
    case never

    nonisolated var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: "Ask each round"
        case .always: "Always track"
        case .never: "Never track"
        }
    }
}

@Observable
final class WorkoutConsentStore {
    static let shared = WorkoutConsentStore()

    private static let modeKey = "workoutConsentMode"

    /// Persisted default behavior.
    var mode: WorkoutConsent {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        }
    }

    /// True while the "Track this round?" sheet should be on screen.
    private(set) var isAsking = false

    /// Rounds already answered this launch — so declining doesn't re-ask
    /// on every snapshot push, and so a fresh round asks again.
    private var answeredRoundKey: String?

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.modeKey)
        mode = raw.flatMap(WorkoutConsent.init(rawValue:)) ?? .ask
    }

    /// Called whenever a round is live. Starts, skips, or prompts
    /// depending on the saved mode. Idempotent per round.
    func roundBecameLive(key: String) {
        guard !WorkoutKeepAliveService.shared.isRunning else { return }

        switch mode {
        case .always:
            WorkoutKeepAliveService.shared.start()
        case .never:
            return
        case .ask:
            guard answeredRoundKey != key, !isAsking else { return }
            pendingRoundKey = key
            isAsking = true
        }
    }

    /// Round ended (or the app has no round) — reset so the next round
    /// asks again, and drop any prompt still on screen.
    func roundEnded() {
        isAsking = false
        pendingRoundKey = nil
        answeredRoundKey = nil
    }

    /// Wearer said yes. `remember` saves it as the new default.
    func accept(remember: Bool) {
        answeredRoundKey = pendingRoundKey
        isAsking = false
        if remember { mode = .always }
        WorkoutKeepAliveService.shared.start()
    }

    /// Wearer said no. `remember` saves it as the new default.
    func decline(remember: Bool) {
        answeredRoundKey = pendingRoundKey
        isAsking = false
        if remember { mode = .never }
    }

    /// Manual start/stop from the round screen's Health badge.
    func startManually() {
        answeredRoundKey = pendingRoundKey
        WorkoutKeepAliveService.shared.start()
    }

    func stopManually() {
        answeredRoundKey = pendingRoundKey
        WorkoutKeepAliveService.shared.end()
    }

    private var pendingRoundKey: String?
}
