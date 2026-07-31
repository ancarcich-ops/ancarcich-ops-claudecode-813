//
//  WatchAppDelegate.swift
//  SticksWatch
//
//  Receives the launch-for-workout handoff from the iPhone. When the
//  phone app opens (or a round starts) it calls HealthKit's
//  `startWatchApp(with:)`, which launches this app and delivers the golf
//  workout configuration here. If a round is actually live, the
//  keep-alive workout is offered — started outright only if the wearer
//  has already chosen "Always track", otherwise the round screen asks
//  first. With no round we skip it entirely — no phantom golf workouts
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
            if let snapshot = session.snapshot {
                WorkoutConsentStore.shared.roundBecameLive(key: snapshot.courseName)
            }
        }
    }
}
