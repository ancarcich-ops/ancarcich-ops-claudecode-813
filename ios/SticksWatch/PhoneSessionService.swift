//
//  PhoneSessionService.swift
//  SticksWatch
//
//  Receives the round snapshot pushed by the iPhone app via the
//  WatchConnectivity application context, and sends interactive commands
//  (hole switching, the wearer's score) to the phone via sendMessage —
//  which wakes the iPhone app in the background, so commands work with
//  the phone locked in a pocket. The watch stays a dumb terminal: no
//  networking, no auth, no course data store.
//

import Foundation
import Observation
import WatchConnectivity

/// Errors from watch → phone commands.
nonisolated enum WatchCommandError: Error {
    /// The iPhone isn't reachable (out of range / session down).
    case notReachable
    /// No reply within the timeout — never leave a spinner forever.
    case timeout
    /// The phone replied with an error message (shown verbatim).
    case phone(String)
}

/// Guards a checked continuation against double-resume — the reply,
/// error, and timeout handlers race on different queues.
private nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    /// Runs `body` only for the first caller.
    func run(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !done
        done = true
        lock.unlock()
        if shouldRun { body() }
    }
}

@Observable
final class PhoneSessionService: NSObject, WCSessionDelegate {
    /// Latest round pushed from the phone — nil when no round is live.
    private(set) var snapshot: RoundSnapshot?

    /// How long a command waits for the phone before giving up.
    private static let commandTimeout: TimeInterval = 5

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

    // MARK: - Commands (watch → phone)

    /// Switches the phone's current hole. `index` is the absolute round
    /// index. Returns the reply snapshot (already merged newer-wins).
    func setHole(index: Int) async throws -> RoundSnapshot {
        try await sendCommand(["cmd": "setHole", "holeIndex": index])
    }

    /// Posts the wearer's own score on `hole` through the phone.
    func sendScore(hole: Int, strokes: Int) async throws -> RoundSnapshot {
        try await sendCommand(["cmd": "score", "hole": hole, "strokes": strokes])
    }

    private func sendCommand(_ message: [String: Any]) async throws -> RoundSnapshot {
        let session = WCSession.default
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isReachable else {
            throw WatchCommandError.notReachable
        }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let resume = ResumeOnce()
            session.sendMessage(message, replyHandler: { reply in
                if let data = reply["round"] as? Data {
                    resume.run { continuation.resume(returning: data) }
                } else {
                    let message = reply["error"] as? String ?? "Something went wrong."
                    resume.run { continuation.resume(throwing: WatchCommandError.phone(message)) }
                }
            }, errorHandler: { _ in
                resume.run { continuation.resume(throwing: WatchCommandError.notReachable) }
            })
            // sendMessage's own timeout can run long — cap it ourselves so
            // the UI never hangs on a spinner.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.commandTimeout) {
                resume.run { continuation.resume(throwing: WatchCommandError.timeout) }
            }
        }

        guard let decoded = try? JSONDecoder().decode(RoundSnapshot.self, from: data) else {
            throw WatchCommandError.phone("Something went wrong.")
        }
        merge(decoded)
        return decoded
    }

    // MARK: - Snapshot merging

    /// Newer-wins merge — a command reply and the next applicationContext
    /// push may arrive in either order, so never blindly overwrite.
    private func merge(_ incoming: RoundSnapshot) {
        if let current = snapshot, current.updatedAt > incoming.updatedAt { return }
        snapshot = incoming
    }

    private func apply(_ data: Data?) {
        guard let data,
              let decoded = try? JSONDecoder().decode(RoundSnapshot.self, from: data) else {
            snapshot = nil
            return
        }
        merge(decoded)
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
