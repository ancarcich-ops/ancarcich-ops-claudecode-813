//
//  FollowBadgeStore.swift
//  Sticks
//
//  Slice 69: the shared incoming follow-request count behind the
//  header dropdown's "People & follows" badge (row + trigger pill).
//  Fetched once when the signed-in root appears and cached briefly;
//  the People screen syncs the truth here as requests change, so
//  accepting/declining clears the badge immediately. A failed fetch
//  just means no badge — it never blocks the menu.
//

import Foundation
import Observation

@Observable
final class FollowBadgeStore {
    static let shared = FollowBadgeStore()

    /// Incoming follow requests awaiting my approval.
    private(set) var requestCount = 0

    private var lastFetch: Date?
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Refreshes the count from GET /follows. Skips the network when a
    /// recent fetch is cached, unless forced.
    func refresh(session: SessionStore, force: Bool = false) async {
        guard let token = session.token else { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 60 {
            return
        }
        do {
            let response = try await api.getFollows(token: token)
            requestCount = response.requests.count
            lastFetch = Date()
        } catch {
            // Non-fatal — a failed fetch just shows no badge.
        }
    }

    /// The People screen pushes its live requests count here so the
    /// badge clears the moment a request is accepted or declined.
    func setCount(_ count: Int) {
        requestCount = max(0, count)
        lastFetch = Date()
    }
}
