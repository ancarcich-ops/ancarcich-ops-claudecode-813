//
//  DisplayPrefsStore.swift
//  Sticks
//
//  Slice 96: the account's display preferences, cached on the device
//  and reconciled with GET/POST /me/display-prefs. Exposes
//  `showReactions`, which hides EVERY reaction row — feed cards, the
//  round-level bar, and the rows under each highlight. The Highlights
//  list itself stays; only the emoji go.
//
//  Deliberately NOT the reactions push toggle: that lives in
//  PushNotificationService (/me/push-prefs) and decides whether the
//  phone buzzes. A quiet screen keeps its notifications.
//
//  Failure policy: a failed fetch or post keeps the last known value
//  (cached in UserDefaults), so the screen the user asked for stays
//  quiet even while offline — the next successful refresh re-syncs
//  with the server.
//

import Foundation

@Observable
final class DisplayPrefsStore {
    static let shared = DisplayPrefsStore()

    private static let cacheKey = "sticks.displayPrefs.v1"
    private static let refreshInterval: TimeInterval = 60

    private let api: APIClient
    private var lastRefreshAt: Date?

    private(set) var showReactions: Bool

    init(api: APIClient = .shared) {
        self.api = api
        showReactions = UserDefaults.standard.object(forKey: Self.cacheKey) as? Bool ?? true
    }

    /// Re-syncs with the server, throttled so the feed, detail, and
    /// Settings can all call it without hammering the endpoint. A
    /// failed call (including a 404 before the route ships) keeps the
    /// cached value.
    func refresh(session: SessionStore) async {
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < Self.refreshInterval {
            return
        }
        lastRefreshAt = Date()
        guard let token = session.token else { return }
        guard let response = try? await api.displayPrefs(token: token) else { return }
        apply(response.prefs.showReactions)
    }

    /// Optimistic toggle — the rows vanish the moment the switch flips —
    /// then the server post. The response's prefs are authoritative
    /// (only a real boolean counts there), so the value reconciles from
    /// the reply.
    func setShowReactions(_ value: Bool, session: SessionStore) async {
        apply(value)
        guard let token = session.token else { return }
        if let response = try? await api.setDisplayPrefs(showReactions: value, token: token) {
            apply(response.prefs.showReactions)
        }
    }

    private func apply(_ value: Bool) {
        showReactions = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }
}
