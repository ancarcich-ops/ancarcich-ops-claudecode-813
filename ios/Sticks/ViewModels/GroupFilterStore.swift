//
//  GroupFilterStore.swift
//  Sticks
//
//  Slice 31: the shared active-group filter behind the header's group
//  switcher. Holds the user's groups (loaded once via GET /groups so
//  the switcher is populated on every tab) and the active filter mode.
//  The selection persists across launches, mirroring the web's
//  active-group cookie.
//  Slice 37: web parity — the filter is now a three-way mode: all
//  rounds, public-only (rounds with no group), or a single group.
//

import Foundation
import Observation

/// The header switcher's feed scope — everything, public-only (rounds
/// not attached to a group), or one group.
nonisolated enum GroupFilterMode: Equatable {
    case all
    case publicOnly
    case group(String)
}

@Observable
final class GroupFilterStore {
    static let shared = GroupFilterStore()

    private static let groupKey = "sticks-active-group-id"
    private static let publicOnlyKey = "sticks-public-only"

    /// The current feed scope. Persisted across launches.
    private(set) var mode: GroupFilterMode
    /// The switcher's menu entries — kept fresh by MainTabView on
    /// matches/groups-changed signals.
    private(set) var groups: [SticksGroup] = []

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        if UserDefaults.standard.bool(forKey: Self.publicOnlyKey) {
            mode = .publicOnly
        } else if let id = UserDefaults.standard.string(forKey: Self.groupKey) {
            mode = .group(id)
        } else {
            mode = .all
        }
    }

    /// The active group's id when a group filter is on, else nil.
    var activeGroupId: String? {
        if case .group(let id) = mode { return id }
        return nil
    }

    var isPublicOnly: Bool { mode == .publicOnly }

    /// Slice 38: the GET /matches?group= value for the active mode —
    /// nil (default feed), "public" (ungrouped only), or a group id
    /// (that group's cross-group set). The server owns the filtering.
    var groupQueryValue: String? {
        switch mode {
        case .all:
            return nil
        case .publicOnly:
            return "public"
        case .group(let id):
            return id
        }
    }

    /// The active group's name for the switcher label, when known.
    var activeGroupName: String? {
        activeGroup?.name
    }

    /// The full active group — used by the menu's leaderboard link.
    var activeGroup: SticksGroup? {
        guard let activeGroupId else { return nil }
        return groups.first { $0.id == activeGroupId }
    }

    /// Sets the filter mode and persists it (like the web's cookie).
    func setMode(_ newMode: GroupFilterMode) {
        mode = newMode
        let defaults = UserDefaults.standard
        switch newMode {
        case .all:
            defaults.removeObject(forKey: Self.groupKey)
            defaults.removeObject(forKey: Self.publicOnlyKey)
        case .publicOnly:
            defaults.removeObject(forKey: Self.groupKey)
            defaults.set(true, forKey: Self.publicOnlyKey)
        case .group(let id):
            defaults.set(id, forKey: Self.groupKey)
            defaults.removeObject(forKey: Self.publicOnlyKey)
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
                setMode(.all)
            }
        } catch {
            // Non-fatal: the header still renders with the stale list.
        }
    }
}
