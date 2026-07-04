//
//  RoundActivityService.swift
//  Sticks
//
//  Manages the on-course Live Activity (lock screen + Dynamic Island).
//  Started when the GPS screen opens on an in-progress match, updated as
//  the hole / yardages / scores change, and ended when the round
//  finishes. The activity intentionally survives leaving the GPS screen
//  so yardages stay glanceable for the whole round.
//

import ActivityKit
import Foundation

final class RoundActivityService {
    static let shared = RoundActivityService()

    private var activity: Activity<RoundActivityAttributes>?
    private var lastState: RoundActivityAttributes.ContentState?

    private init() {}

    /// Starts the activity on first call (adopting one that survived an
    /// app relaunch and ending stale ones from other matches), then keeps
    /// it updated. Deduplicated, so calling on every view change is cheap.
    func startOrUpdate(matchId: String, courseName: String, state: RoundActivityAttributes.ContentState) {
        if activity == nil {
            activity = Activity<RoundActivityAttributes>.activities.first { $0.attributes.matchId == matchId }
        }
        for stale in Activity<RoundActivityAttributes>.activities where stale.attributes.matchId != matchId {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }

        if let activity {
            guard state != lastState else { return }
            lastState = state
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        lastState = state
        activity = try? Activity.request(
            attributes: RoundActivityAttributes(courseName: courseName, matchId: matchId),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    /// Ends and dismisses the activity (round finished or match completed).
    func end() {
        let current = activity ?? Activity<RoundActivityAttributes>.activities.first
        activity = nil
        lastState = nil
        guard let current else { return }
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }
}
