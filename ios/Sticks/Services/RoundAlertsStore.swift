//
//  RoundAlertsStore.swift
//  Sticks
//
//  Slice 72: per-round alert overrides ("follow this match"). Keeps the
//  chosen mode per match id locally (instant UI, survives relaunch) and
//  mirrors it to POST /matches/:id/alerts — the SERVER gates fanout, so
//  a failed mirror is queued and retried the next time that round's
//  screen loads.
//

import Foundation
import Observation

@Observable
final class RoundAlertsStore {
    static let shared = RoundAlertsStore()

    /// matchId → override. `.standard` rounds are absent (no override).
    private(set) var modes: [String: RoundAlertMode] = [:]
    /// Rounds whose local choice hasn't reached the server yet.
    private(set) var pendingSync: Set<String> = []

    private static let modesKey = "sticks.roundAlertModes.v1"
    private static let pendingKey = "sticks.roundAlertPending.v1"

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.modesKey),
           let saved = try? JSONDecoder().decode([String: RoundAlertMode].self, from: data) {
            modes = saved
        }
        pendingSync = Set(defaults.stringArray(forKey: Self.pendingKey) ?? [])
    }

    func mode(for matchId: String) -> RoundAlertMode {
        modes[matchId] ?? .standard
    }

    /// Applies a choice immediately, then mirrors it to the server.
    func setMode(_ mode: RoundAlertMode, for matchId: String) {
        if mode == .standard {
            modes.removeValue(forKey: matchId)
        } else {
            modes[matchId] = mode
        }
        pendingSync.insert(matchId)
        persist()
        Task { await mirror(mode, matchId: matchId) }
    }

    /// Adopts the server's stored override for a round (another device
    /// may have set it). A round whose local choice is still unsynced
    /// wins — its pending value is pushed instead.
    func refresh(matchId: String) async {
        guard let token = KeychainService.loadToken() else { return }
        if pendingSync.contains(matchId) {
            await mirror(mode(for: matchId), matchId: matchId)
            return
        }
        guard let serverMode = try? await api.roundAlertMode(matchId: matchId, token: token) else { return }
        guard serverMode != mode(for: matchId) else { return }
        if serverMode == .standard {
            modes.removeValue(forKey: matchId)
        } else {
            modes[matchId] = serverMode
        }
        persist()
    }

    /// Sign-out cleanup — overrides belong to the account, not the device.
    func clearAll() {
        modes = [:]
        pendingSync = []
        persist()
    }

    // MARK: - Plumbing

    private func mirror(_ mode: RoundAlertMode, matchId: String) async {
        guard let token = KeychainService.loadToken() else { return }
        do {
            try await api.setRoundAlertMode(mode, matchId: matchId, token: token)
            pendingSync.remove(matchId)
            persist()
        } catch {
            // Soft failure (offline, or the endpoint isn't live yet) —
            // retried when this round's screen next loads.
            let message = (error as? APIError)?.message ?? error.localizedDescription
            print("[Push] Round alert mirror failed for \(matchId): \(message)")
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(modes) {
            defaults.set(data, forKey: Self.modesKey)
        }
        defaults.set(Array(pendingSync), forKey: Self.pendingKey)
    }
}
