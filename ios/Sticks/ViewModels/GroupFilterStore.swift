//
//  GroupFilterStore.swift
//  Sticks
//
//  Slice 31: the shared active-group filter behind the header's group
//  switcher. Holds the user's groups (loaded once via GET /groups so
//  the switcher is populated on every tab) and the active group id —
//  nil means "All my groups". The selection persists across launches,
//  mirroring the web's active-group cookie.
//

import Foundation
import Observation

@Observable
final class GroupFilterStore {
    static let shared = GroupFilterStore()

    private static let storageKey = "sticks-active-group-id"

    /// nil = "All my groups" (no filtering).
    private(set) var activeGroupId: String?
    /// The switcher's menu entries — kept fresh by MainTabView on
    /// matches/groups-changed signals.
    private(set) var groups: [SticksGroup] = []

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        activeGroupId = UserDefaults.standard.string(forKey: Self.storageKey)
    }

    /// The active group's name for the switcher label, when known.
    var activeGroupName: String? {
        guard let activeGroupId else { return nil }
        return groups.first { $0.id == activeGroupId }?.name
    }

    /// Sets (or clears, with nil) the active group and persists it.
    func setActiveGroup(_ id: String?) {
        activeGroupId = id
        if let id {
            UserDefaults.standard.set(id, forKey: Self.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }

    /// Refreshes the switcher's groups. Failures keep the last list —
    /// the switcher degrades to "All my groups" plus whatever loaded.
    func load(session: SessionStore) async {
        guard let token = session.token else { return }
        do {
            let response = try await api.groups(token: token)
            groups = response.groups
            // A persisted selection pointing at a group the user left
            // (or that was deleted) would filter the feed invisibly.
            if let activeGroupId, !groups.contains(where: { $0.id == activeGroupId }) {
                setActiveGroup(nil)
            }
        } catch {
            // Non-fatal: the header still renders with the stale list.
        }
    }
}
