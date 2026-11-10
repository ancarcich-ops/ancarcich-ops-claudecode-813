//
//  HighlightFoldStore.swift
//  Sticks
//
//  Slice 96: the per-round "hide highlights" fold, remembered ON THE
//  DEVICE — there is deliberately no API for this. It's a per-round
//  display choice that doesn't need to follow anyone between devices,
//  and losing it on a new phone costs one tap.
//
//  Persisted as a set of match ids in UserDefaults, so a folded round
//  STAYS folded across score entry, navigation, and an app restart —
//  and never springs open when a new score lands, which is the whole
//  point. Other rounds are unaffected (keyed by match id).
//

import Foundation

@Observable
final class HighlightFoldStore {
    static let shared = HighlightFoldStore()

    private static let storageKey = "sticks.highlightFolds.v1"

    private var foldedMatchIds: Set<String>

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            foldedMatchIds = decoded
        } else {
            foldedMatchIds = []
        }
    }

    func isFolded(_ matchId: String) -> Bool {
        foldedMatchIds.contains(matchId)
    }

    func setFolded(_ value: Bool, matchId: String) {
        if value {
            foldedMatchIds.insert(matchId)
        } else {
            foldedMatchIds.remove(matchId)
        }
        if let data = try? JSONEncoder().encode(foldedMatchIds) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
