//
//  WatchAppDelegate.swift
//  SticksWatch
//
//  Receives the launch-for-workout handoff from the iPhone. When the
//  phone app opens (or a round starts) it calls HealthKit's
//  `startWatchApp(with:)`, which launches this app and delivers the golf
//  workout configuration here. If a round is actually live, the
//  keep-alive workout starts immediately so Sticks lands frontmost on the
//  wrist; with no round we skip the workout — no phantom golf workouts
//  in Health from just browsing the phone app.
//

import Foundation
import HealthKit
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    nonisolated func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            let session = PhoneSessionService.shared
            // Pull any context delivered while the app was closed so the
            // live-round check below sees the current state.
            session.activate()
            if session.snapshot != nil {
                WorkoutKeepAliveService.shared.start()
            }
        }
    }
}
