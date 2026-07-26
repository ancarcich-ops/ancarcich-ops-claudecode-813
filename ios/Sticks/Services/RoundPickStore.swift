//
//  RoundPickStore.swift
//  Sticks
//
//  Crowd picks placed straight from the home feed. The match-list payload
//  may or may not carry the caller's pick, so the store keeps the last
//  known pick per round locally (instant chips, survives relaunch) and
//  adopts the server's value whenever a payload includes market fields.
//  Placing a pick reuses POST /matches/:id/call — the same endpoint the
//  match page's Market uses — so home and detail always agree.
//

import Foundation
import Observation

@Observable
final class RoundPickStore {
    static let shared = RoundPickStore()

    /// matchId → picked matchPlayerId. Rounds without a pick are absent.
    private(set) var picks: [String: String] = [:]
    /// matchId → (matchPlayerId → crowd pick count), best known values.
    private(set) var counts: [String: [String: Int]] = [:]
    /// matchId → matchPlayerId whose pick request is in flight.
    private(set) var pending: [String: String] = [:]

    private static let picksKey = "sticks.roundPicks.v1"

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        if let data = UserDefaults.standard.data(forKey: Self.picksKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            picks = saved
        }
    }

    func pick(for matchId: String) -> String? { picks[matchId] }

    func pickCount(matchId: String, playerId: String) -> Int {
        counts[matchId]?[playerId] ?? 0
    }

    func isPending(matchId: String, playerId: String) -> Bool {
        pending[matchId] == playerId
    }

    func isBusy(matchId: String) -> Bool { pending[matchId] != nil }

    /// Adopts the server's market state for a round when the payload
    /// actually carried it (another device may have placed the pick).
    /// Rounds with a request in flight keep their optimistic value.
    func adopt(from match: MatchSummary) {
        guard match.hasCallData, pending[match.id] == nil else { return }
        if !match.wagerCounts.isEmpty {
            counts[match.id] = match.wagerCounts
        }
        let current = picks[match.id]
        guard match.myCall != current else { return }
        if let call = match.myCall {
            picks[match.id] = call
        } else {
            picks.removeValue(forKey: match.id)
        }
        persist()
    }

    /// Places (or withdraws, when `playerId` is already the pick) the
    /// caller's crowd pick. Applies optimistically, reverts on failure.
    /// Throws APIError so callers can surface the server's message.
    func toggle(playerId: String, matchId: String) async throws {
        guard pending[matchId] == nil else { return }
        guard let token = KeychainService.loadToken() else {
            throw APIError(message: "You've been signed out.", statusCode: 401)
        }

        let previous = picks[matchId]
        let previousCounts = counts[matchId]
        let picked: String? = previous == playerId ? nil : playerId

        pending[matchId] = playerId
        applyOptimistic(picked, previous: previous, matchId: matchId)

        do {
            let result = try await api.placeCall(
                matchId: matchId,
                pickedPlayerId: picked,
                token: token
            )
            pending.removeValue(forKey: matchId)
            if let call = result.myCall {
                picks[matchId] = call
            } else {
                picks.removeValue(forKey: matchId)
            }
            if !result.wagerCounts.isEmpty {
                counts[matchId] = result.wagerCounts
            }
            persist()
        } catch {
            pending.removeValue(forKey: matchId)
            if let previous {
                picks[matchId] = previous
            } else {
                picks.removeValue(forKey: matchId)
            }
            counts[matchId] = previousCounts
            persist()
            throw error
        }
    }

    /// Sign-out cleanup — picks belong to the account, not the device.
    func clearAll() {
        picks = [:]
        counts = [:]
        pending = [:]
        persist()
    }

    // MARK: - Plumbing

    /// Moves the local pick and nudges the visible counts so the chip and
    /// the count read correctly before the server answers.
    private func applyOptimistic(_ picked: String?, previous: String?, matchId: String) {
        var matchCounts = counts[matchId] ?? [:]
        if let previous {
            matchCounts[previous] = max((matchCounts[previous] ?? 1) - 1, 0)
        }
        if let picked {
            matchCounts[picked] = (matchCounts[picked] ?? 0) + 1
            picks[matchId] = picked
        } else {
            picks.removeValue(forKey: matchId)
        }
        if !matchCounts.isEmpty {
            counts[matchId] = matchCounts
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(picks) else { return }
        UserDefaults.standard.set(data, forKey: Self.picksKey)
    }
}
