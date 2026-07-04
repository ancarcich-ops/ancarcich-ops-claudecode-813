//
//  PhoneSessionService.swift
//  SticksWatch
//
//  Receives the round snapshot pushed by the iPhone app via the
//  WatchConnectivity application context.
//

import Foundation
import Observation
import WatchConnectivity

@Observable
final class PhoneSessionService: NSObject, WCSessionDelegate {
    /// Latest round pushed from the phone — nil when no round is live.
    private(set) var snapshot: RoundSnapshot?

    /// Activates the session (idempotent) and applies any context that
    /// was delivered while the watch app was closed.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
        }
        apply(session.receivedApplicationContext["round"] as? Data)
    }

    private func apply(_ data: Data?) {
        guard let data,
              let decoded = try? JSONDecoder().decode(RoundSnapshot.self, from: data) else {
            snapshot = nil
            return
        }
        snapshot = decoded
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["round"] as? Data
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["round"] as? Data
        Task { @MainActor in self.apply(data) }
    }
}
