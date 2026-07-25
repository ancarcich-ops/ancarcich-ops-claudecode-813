//
//  PushPrefs.swift
//  Sticks
//
//  Slice 71: per-category remote-push toggles. Stored locally (instant
//  UI) and mirrored to the server via /me/push-prefs — the SERVER is
//  what actually gates fanout, so a failed mirror is retried on the
//  next change or launch. Unknown/missing keys decode as `true` so new
//  categories default on for existing users.
//

import Foundation

nonisolated struct PushPrefs: Codable, Equatable {
    /// Someone you follow (or a group member) tees off.
    var roundStarts: Bool
    /// Birdie, eagle, albatross, or ace posted mid-round.
    var birdiesAndBetter: Bool
    /// A player makes the turn — front-nine total.
    var frontNineScores: Bool
    /// Full-round final scores when a round completes.
    var finalScores: Bool
    /// Incoming follow requests + accepted requests.
    var followRequests: Bool

    init(
        roundStarts: Bool = true,
        birdiesAndBetter: Bool = true,
        frontNineScores: Bool = true,
        finalScores: Bool = true,
        followRequests: Bool = true
    ) {
        self.roundStarts = roundStarts
        self.birdiesAndBetter = birdiesAndBetter
        self.frontNineScores = frontNineScores
        self.finalScores = finalScores
        self.followRequests = followRequests
    }

    private enum CodingKeys: String, CodingKey {
        case roundStarts, birdiesAndBetter, frontNineScores, finalScores, followRequests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roundStarts = (try? container.decode(Bool.self, forKey: .roundStarts)) ?? true
        birdiesAndBetter = (try? container.decode(Bool.self, forKey: .birdiesAndBetter)) ?? true
        frontNineScores = (try? container.decode(Bool.self, forKey: .frontNineScores)) ?? true
        finalScores = (try? container.decode(Bool.self, forKey: .finalScores)) ?? true
        followRequests = (try? container.decode(Bool.self, forKey: .followRequests)) ?? true
    }
}
