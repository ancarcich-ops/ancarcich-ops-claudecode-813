//
//  PushPrefs.swift
//  Sticks
//
//  Slice 71: per-category remote-push toggles. Stored locally (instant
//  UI) and mirrored to the server via /me/push-prefs — the SERVER is
//  what actually gates fanout, so a failed mirror is retried on the
//  next change or launch.
//
//  Slice 93: the category set is now DYNAMIC. The server returns seven
//  bare bool keys (tournaments and reactions joined the original five)
//  and may add more, so prefs decode every bool key they see — known
//  keys default ON when missing, unknown keys are preserved verbatim —
//  and encode back flattened, which is byte-compatible with the old
//  saved shape and the POST body.
//

import Foundation

nonisolated struct PushPrefs: Codable, Equatable {
    /// Server key → enabled. Missing keys mean ON.
    private(set) var values: [String: Bool]

    /// The categories the app knows, in display order, with their
    /// Settings copy. Anything the server adds beyond these still
    /// renders (humanized) so a toggle always exists for every key.
    static let categories: [(key: String, label: String, caption: String)] = [
        ("roundStarts", "ROUND STARTS", "When someone you follow or share a group with tees off."),
        ("birdiesAndBetter", "BIRDIES & BETTER", "Birdies, eagles, and aces as they land."),
        ("frontNineScores", "FRONT 9 SCORES", "When a player makes the turn."),
        ("finalScores", "FINAL SCORES", "Full-round results when a round wraps."),
        ("tournaments", "TOURNAMENTS", "Tournament starts, standings, and results."),
        ("reactions", "REACTIONS", "When someone reacts to your scores."),
        ("followRequests", "FOLLOW REQUESTS", "New follow requests and accepts."),
    ]

    init() {
        values = Dictionary(uniqueKeysWithValues: Self.categories.map { ($0.key, true) })
    }

    subscript(key: String) -> Bool {
        get { values[key] ?? true }
        set { values[key] = newValue }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        // Missing keys default on; unknown keys round-trip untouched.
        var merged = Dictionary(uniqueKeysWithValues: Self.categories.map { ($0.key, true) })
        for key in container.allKeys {
            if let value = try? container.decode(Bool.self, forKey: key) {
                merged[key.stringValue] = value
            }
        }
        values = merged
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in values {
            if let dynamicKey = DynamicKey(stringValue: key) {
                try container.encode(value, forKey: dynamicKey)
            }
        }
    }
}
