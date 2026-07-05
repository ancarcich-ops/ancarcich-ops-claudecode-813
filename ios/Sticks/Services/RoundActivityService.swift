//
//  RoundActivityService.swift
//  Sticks
//
//  Manages the on-course Live Activity (lock screen + Dynamic Island).
//  ROUND-scoped, driven by RoundSessionService: requested the first time
//  the GPS screen opens on an in-progress match, updated as the hole /
//  scores / TO PIN change (surviving navigation, backgrounding, and phone
//  lock), and ended on FINISH ROUND, the poll reporting COMPLETED,
//  sign-out, or switching to a different match's round. The staleDate
//  backstop covers force-quit and system kills.
//  Everything is local — no push tokens, no server involvement.
//

import ActivityKit
import Foundation

final class RoundActivityService {
    static let shared = RoundActivityService()

    /// Backstop for when iOS suspends the app in a pocket: after this
    /// passes without an update, the system marks the activity stale and
    /// the widget renders the "OPEN STICKS TO REFRESH" state.
    private static let staleInterval: TimeInterval = 5 * 60
    /// At most one ActivityKit update per second.
    private static let minPushInterval: TimeInterval = 1
    /// TO PIN movement below this many yards doesn't trigger an update.
    private static let toPinDeltaYds = 5

    private var activity: Activity<RoundActivityAttributes>?
    private var lastPushedState: RoundActivityAttributes.ContentState?
    private var lastPushAt: Date = .distantPast
    private var pendingPush: Task<Void, Never>?
    private var isStarting = false

    private init() {}

    /// Requests the activity on first call — ending ALL pre-existing
    /// activities first (stragglers from a killed app), so exactly one
    /// ever runs — then keeps it updated. Cheap to call on every view
    /// change: it pushes only when the hole changes, a score lands, or
    /// TO PIN moves ≥ 5 yards, throttled to one update per second.
    func startOrUpdate(matchId: String, courseName: String, state: RoundActivityAttributes.ContentState) {
        if let activity {
            guard shouldPush(state) else { return }
            schedulePush(state, to: activity)
            return
        }
        guard !isStarting else { return }
        // User disabled Live Activities — skip silently, never block the GPS screen.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        isStarting = true
        let stragglers = Activity<RoundActivityAttributes>.activities
        Task {
            for straggler in stragglers {
                await straggler.end(nil, dismissalPolicy: .immediate)
            }
            request(matchId: matchId, courseName: courseName, state: state)
            isStarting = false
        }
    }

    /// Ends and dismisses the activity immediately (round end: FINISH
    /// ROUND success, the poll reporting COMPLETED, sign-out, or a match
    /// switch). Sweeps every activity for the app so none can linger.
    func end() {
        pendingPush?.cancel()
        pendingPush = nil
        activity = nil
        lastPushedState = nil
        lastPushAt = .distantPast
        Task {
            for activity in Activity<RoundActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func request(matchId: String, courseName: String, state: RoundActivityAttributes.ContentState) {
        do {
            var stamped = state
            stamped.updatedAt = Date()
            activity = try Activity.request(
                attributes: RoundActivityAttributes(matchId: matchId, courseName: courseName),
                content: ActivityContent(state: stamped, staleDate: Date().addingTimeInterval(Self.staleInterval)),
                pushType: nil
            )
            lastPushedState = stamped
            lastPushAt = Date()
        } catch {
            // Throws when NSSupportsLiveActivities is missing or the user
            // denied — must stay invisible to the user.
            print("[RoundActivity] request failed: \(error.localizedDescription)")
        }
    }

    /// Push only when something worth waking the lock screen for changed:
    /// the displayed hole, a saved score, or TO PIN moving ≥ 5 yards.
    private func shouldPush(_ new: RoundActivityAttributes.ContentState) -> Bool {
        guard let old = lastPushedState else { return true }
        if new.hole != old.hole || new.par != old.par { return true }
        if new.holesScored != old.holesScored || new.totalHoles != old.totalHoles { return true }
        if new.myToPar != old.myToPar { return true }
        // A wearer score landing flips a strip segment even when neither
        // holesScored (all-players gate) nor myToPar (a par) moves.
        if new.holeDiffs != old.holeDiffs { return true }
        switch (old.toPinYds, new.toPinYds) {
        case (nil, nil):
            break
        case let (oldYds?, newYds?):
            if abs(newYds - oldYds) >= Self.toPinDeltaYds { return true }
        default:
            return true // GPS fix gained or lost
        }
        return false
    }

    /// Pushes now, or trails behind the 1-second throttle window
    /// (coalescing to the latest state).
    private func schedulePush(_ state: RoundActivityAttributes.ContentState, to activity: Activity<RoundActivityAttributes>) {
        pendingPush?.cancel()
        let wait = Self.minPushInterval - Date().timeIntervalSince(lastPushAt)
        if wait <= 0 {
            push(state, to: activity)
            return
        }
        pendingPush = Task {
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            push(state, to: activity)
        }
    }

    private func push(_ state: RoundActivityAttributes.ContentState, to activity: Activity<RoundActivityAttributes>) {
        var stamped = state
        stamped.updatedAt = Date()
        lastPushedState = stamped
        lastPushAt = Date()
        Task {
            await activity.update(
                ActivityContent(state: stamped, staleDate: Date().addingTimeInterval(Self.staleInterval))
            )
        }
    }
}
