//
//  Reactions.swift
//  Sticks
//
//  Slice 93: round + hole reactions and server-computed score highlights.
//
//  Shapes (probed live against /api/mobile):
//  - List payloads carry per-round tallies only: reactions: [Reaction].
//  - Detail adds reactionEmoji (the server's render order), a
//    reactions map keyed by target ("round" or "hole:<matchPlayerId>:<hole>"),
//    and highlights (already sorted — render as-is, never re-sort).
//  - POST /matches/:id/reactions { emoji, matchPlayerId?, hole? } →
//    { ok, added, reactions } where reactions is the target's FULL
//    post-toggle tally. matchPlayerId + hole must be sent together or
//    neither; a hole without a player is a 400, as is an unscored hole.
//

import Foundation

/// One emoji's tally on a reaction target (the round, or a scored hole).
nonisolated struct Reaction: Codable, Hashable {
    let emoji: String
    let count: Int
    let mine: Bool

    /// The tally after the caller's tap — the optimistic flip shown
    /// until the server's authoritative post-toggle tally lands.
    func toggled() -> Reaction {
        Reaction(emoji: emoji, count: max(0, mine ? count - 1 : count + 1), mine: !mine)
    }
}

extension Reaction {
    /// Card fallback set — the list payload carries tallies only, not
    /// the server's emoji order, so home cards render this constant.
    /// Detail screens use the server's `reactionEmoji` instead.
    /// v2 set per docs/reactions-v2-spec.md (💀 replaces 😬, 🍺 added).
    static let fallbackEmojiSet = ["❤️", "🔥", "😂", "👏", "💀", "🍺"]
}

/// POST /matches/:id/reactions body — nil fields are omitted, so the
/// round-level toggle sends `emoji` alone and hole-level sends
/// matchPlayerId + hole together (the server rejects any other mix).
nonisolated struct ReactionRequest: Encodable {
    let emoji: String
    let matchPlayerId: String?
    let hole: Int?
}

/// POST /matches/:id/reactions response — `added` is false when the tap
/// removed the caller's own reaction.
nonisolated struct ReactionToggleResponse: Decodable {
    let ok: Bool
    let added: Bool
    let reactions: [Reaction]
}

/// One server-computed score highlight ("EAGLE", "SNOWMAN", …).
/// Rendered exactly as sent — the server owns sorting and copy.
nonisolated struct MatchHighlight: Decodable, Hashable {
    let matchPlayerId: String
    let displayName: String
    let hole: Int
    let strokes: Int
    let par: Int
    let label: String
    /// "good" | "bad"
    let tone: String
    /// The reaction key highlights attach to — "hole:<matchPlayerId>:<hole>".
    let reactionKey: String

    private enum CodingKeys: String, CodingKey {
        case matchPlayerId, displayName, hole, strokes, par, label, tone, reactionKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchPlayerId = (try? container.decode(String.self, forKey: .matchPlayerId)) ?? ""
        displayName = (try? container.decode(String.self, forKey: .displayName)) ?? ""
        hole = (try? container.decode(Int.self, forKey: .hole)) ?? 0
        strokes = (try? container.decode(Int.self, forKey: .strokes)) ?? 0
        par = (try? container.decode(Int.self, forKey: .par)) ?? 0
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        tone = (try? container.decode(String.self, forKey: .tone)) ?? "good"
        reactionKey = (try? container.decode(String.self, forKey: .reactionKey)) ?? ""
    }
}

/// Reaction-target helpers shared by the view models.
nonisolated enum ReactionTarget {
    /// Round-level key — the literal string the server uses.
    static let roundKey = "round"

    /// Parses a hole-level key ("hole:<matchPlayerId>:<hole>") into the
    /// pair the reactions endpoint requires — nil for "round".
    static func holePlayerId(forKey key: String) -> (matchPlayerId: String, hole: Int)? {
        guard key.hasPrefix("hole:") else { return nil }
        let parts = key.dropFirst("hole:".count).split(separator: ":")
        guard parts.count == 2, let hole = Int(parts[1]) else { return nil }
        return (String(parts[0]), hole)
    }
}

/// ScrollView anchor for the detail screen's highlights section — what a
/// reaction push ("someone reacted to Seuss.md's eagle") scrolls to.
enum HighlightScrollAnchor {
    static let id = "sticks-highlights"
}

/// A reaction push's scroll target, parked by the deep-link router for
/// the detail screen to consume once its content has loaded.
@MainActor
enum PendingHighlightScroll {
    private static var pending: [String: String] = [:]

    static func park(matchId: String, targetKey: String) {
        pending[matchId] = targetKey
    }

    static func consume(matchId: String) -> String? {
        pending.removeValue(forKey: matchId)
    }
}
