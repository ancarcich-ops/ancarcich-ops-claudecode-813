//
//  WatchSessionService.swift
//  Sticks
//
//  Pushes a glanceable round snapshot to the SticksWatch companion via
//  the WatchConnectivity application context (latest-wins, delivered
//  even when the watch app is closed), and answers interactive commands
//  from the watch (hole switching, score entry) — sendMessage wakes this
//  app in the background, so commands work with the phone locked.
//

import Foundation
import WatchConnectivity

/// Outcome of a watch → phone command, produced by RoundSessionService.
nonisolated enum WatchCommandReply {
    case snapshot(RoundSnapshot)
    case failure(String)
}

/// WCSession's replyHandler is not Sendable-annotated — this box carries
/// it onto the main actor. Safe: WatchConnectivity accepts the reply from
/// any thread, and the handler is called exactly once.
private struct WatchReplyBox: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
}

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

    /// Watch → phone commands. Delegate callbacks arrive on a BACKGROUND
    /// queue — primitives are extracted here, then the command is applied
    /// on the main actor through RoundSessionService / the view model.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let cmd = message["cmd"] as? String
        let holeIndex = message["holeIndex"] as? Int
        let hole = message["hole"] as? Int
        let strokes = message["strokes"] as? Int
        let reply = WatchReplyBox(handler: replyHandler)

        Task { @MainActor in
            let outcome: WatchCommandReply
            switch cmd {
            case "setHole":
                if let holeIndex {
                    outcome = RoundSessionService.shared.applyWatchSetHole(index: holeIndex)
                } else {
                    outcome = .failure("Bad command.")
                }
            case "score":
                if let hole, let strokes {
                    outcome = await RoundSessionService.shared.applyWatchScore(hole: hole, strokes: strokes)
                } else {
                    outcome = .failure("Bad command.")
                }
            default:
                outcome = .failure("Bad command.")
            }

            switch outcome {
            case .snapshot(let snapshot):
                if let data = try? JSONEncoder().encode(snapshot) {
                    reply.handler(["round": data])
                } else {
                    reply.handler(["error": "Couldn't read the round. Try again."])
                }
            case .failure(let message):
                reply.handler(["error": message])
            }
        }
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
