//
//  WatchSessionService.swift
//  Sticks
//
//  Pushes a glanceable round snapshot to the SticksWatch companion via
//  the WatchConnectivity application context (latest-wins, delivered
//  even when the watch app is closed).
//

import Foundation
import WatchConnectivity

final class WatchSessionService: NSObject, WCSessionDelegate {
    static let shared = WatchSessionService()

    private enum Payload {
        case none
        case clear
        case snapshot(RoundSnapshot)
    }

    private var pending: Payload = .none
    private var lastSent: RoundSnapshot?

    private override init() {
        super.init()
    }

    /// Activates the session (idempotent) — call before send/clear.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    /// Queues the snapshot; sent immediately once the session is active.
    func send(_ snapshot: RoundSnapshot) {
        pending = .snapshot(snapshot)
        flush()
    }

    /// Returns the watch to its "no active round" state.
    func clear() {
        pending = .clear
        lastSent = nil
        flush()
    }

    private func flush() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        switch pending {
        case .none:
            break
        case .clear:
            pending = .none
            try? session.updateApplicationContext([:])
        case .snapshot(let snapshot):
            pending = .none
            if let lastSent, snapshot.isSameRoundState(as: lastSent) { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            do {
                try session.updateApplicationContext(["round": data])
                lastSent = snapshot
            } catch {
                // Not paired / watch app not installed — nothing to do.
            }
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in WCSession.default.activate() }
    }
}

private extension RoundSnapshot {
    /// Equality ignoring `updatedAt` — used to dedupe context pushes.
    func isSameRoundState(as other: RoundSnapshot) -> Bool {
        var normalized = other
        normalized.updatedAt = updatedAt
        return normalized == self
    }
}
