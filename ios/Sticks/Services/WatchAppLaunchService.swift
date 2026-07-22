//
//  WatchAppLaunchService.swift
//  Sticks
//
//  Auto-launches the SticksWatch companion app whenever this app comes to
//  the foreground. HealthKit's `startWatchApp(with:)` is the only
//  supported way for an iPhone app to launch its watch app — it delivers
//  a golf workout configuration, and the watch starts its keep-alive
//  workout session only if a round is actually live (no phantom workouts
//  from just browsing the app at home).
//
//  Degrades silently: no paired watch, watch app not installed, or the
//  WatchConnectivity session not yet activated all mean "do nothing".
//

import Foundation
import HealthKit
import WatchConnectivity

final class WatchAppLaunchService {
    static let shared = WatchAppLaunchService()

    private let store = HKHealthStore()
    /// Debounce — scene-phase flaps and activation callbacks can fire in
    /// quick succession; one launch per window is plenty.
    private var lastAttempt: Date?
    private static let debounce: TimeInterval = 20

    private init() {}

    /// Fires `startWatchApp` if a paired watch with SticksWatch installed
    /// is available. Safe to call often — debounced and idempotent (an
    /// already-running watch app is simply brought forward).
    func launchCompanionAppIfPossible() {
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }

        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.debounce { return }
        lastAttempt = Date()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .golf
        configuration.locationType = .outdoor

        store.startWatchApp(with: configuration) { _, error in
            if let error {
                // Watch busy / locked / off-wrist — nothing actionable.
                print("[WatchAppLaunch] startWatchApp failed: \(error.localizedDescription)")
            }
        }
    }
}
