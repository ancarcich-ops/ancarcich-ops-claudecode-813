//
//  WorkoutKeepAliveService.swift
//  SticksWatch
//
//  Keeps the watch app frontmost for the whole round. watchOS sends a
//  normal app back to the clock face ~2 minutes after wrist-down; the
//  only supported way to stay at the front of the stack — so wrist-raise
//  comes straight back to Sticks all round long — is an active
//  HKWorkoutSession. We run a golf workout while a round is live, which
//  also saves the round to Health (heart rate, calories, ring credit).
//
//  If HealthKit is unavailable or the wearer declines permission, this
//  silently does nothing — the app works exactly as before, it just
//  won't stay frontmost.
//

import Foundation
import HealthKit
import Observation
import os

@Observable
final class WorkoutKeepAliveService: NSObject {
    /// Single instance shared by the scene and the app delegate — start
    /// and end must always guard against the same session.
    static let shared = WorkoutKeepAliveService()

    /// True while the golf workout session is live.
    private(set) var isRunning = false

    /// Set once a workout has been written to Health this launch — the
    /// round screen and Settings copy both claim ring credit, so a failed
    /// save must be visible rather than silent.
    private(set) var didSaveLastWorkout = false

    private static let log = Logger(subsystem: "com.sticks.watch", category: "workout")

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Guards start/end against racing an in-flight transition.
    private var isTransitioning = false

    /// Starts the golf session. Idempotent — safe to call on every
    /// snapshot push.
    func start() {
        guard HKHealthStore.isHealthDataAvailable(), !isRunning, !isTransitioning else { return }
        isTransitioning = true
        Task {
            await begin()
            isTransitioning = false
        }
    }

    /// Ends the session and saves the round to Health as a golf workout.
    func end() {
        guard isRunning, !isTransitioning else { return }
        isTransitioning = true
        Task {
            await finish()
            isTransitioning = false
        }
    }

    private func begin() async {
        do {
            try await store.requestAuthorization(
                toShare: [HKQuantityType.workoutType()],
                read: [
                    HKQuantityType(.heartRate),
                    HKQuantityType(.activeEnergyBurned),
                    HKQuantityType(.distanceWalkingRunning),
                ]
            )

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .golf
            configuration.locationType = .outdoor

            let newSession = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            newSession.delegate = self

            session = newSession
            builder = newBuilder

            let start = Date()
            newSession.startActivity(with: start)
            try await newBuilder.beginCollection(at: start)
            didSaveLastWorkout = false
            Self.log.info("Golf workout started")
            // Brand the saved workout so it reads as "Sticks" in Health.
            try? await newBuilder.addMetadata([HKMetadataKeyWorkoutBrandName: "Sticks"])
            isRunning = true
        } catch {
            // Denied permission / no HealthKit — degrade gracefully.
            teardown()
        }
    }

    private func finish() async {
        guard let session, let builder else {
            teardown()
            return
        }
        let end = Date()

        // Order matters. `endCollection` on a session that is still
        // running throws, `finishWorkout` then returns nil, and the round
        // is silently never written to Health. So: stop the activity, ask
        // the session to end, wait for it to actually reach `.ended`, and
        // only then close the builder.
        session.stopActivity(with: end)
        session.end()
        await waitForSessionEnd(session)

        do {
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            didSaveLastWorkout = workout != nil
            if let workout {
                Self.log.info("Golf workout saved to Health, duration \(Int(workout.duration))s")
            } else {
                Self.log.error("finishWorkout returned no workout — nothing saved to Health")
            }
        } catch {
            didSaveLastWorkout = false
            Self.log.error("Failed to save golf workout: \(error.localizedDescription, privacy: .public)")
        }

        teardown()
    }

    /// Polls up to 5s for the session to leave the running/stopped states.
    /// The delegate callback can arrive on any queue, and a hung session
    /// must never block the save forever.
    private func waitForSessionEnd(_ session: HKWorkoutSession) async {
        let deadline = Date().addingTimeInterval(5)
        while session.state != .ended, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if session.state != .ended {
            Self.log.error("Workout session did not reach .ended in time; saving anyway")
        }
    }

    private func teardown() {
        session = nil
        builder = nil
        isRunning = false
    }
}

extension WorkoutKeepAliveService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Session died underneath us (rare) — reset so the next snapshot
        // push can start a fresh one.
        Task { @MainActor in self.teardown() }
    }
}
